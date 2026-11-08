/* Olive Branch operator console mockup. SAMPLE DATA only. Plain JS, no dependencies.
 * Layout: helpers -> components (panel/tile/charts/table) -> views -> actions -> chrome (palette, dialogs) -> boot. */
(() => {
'use strict';
const O = window.OPS;
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const store = { get(k, d) { try { const v = localStorage.getItem('obops.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } }, set(k, v) { try { localStorage.setItem('obops.' + k, JSON.stringify(v)); } catch { /* storage may be blocked */ } } };

// ---------------------------------------------------------------- state
const state = {
  env: store.get('env', 'prod'), range: store.get('range', '24h'), theme: store.get('theme', null),
  route: 'overview', faults: { stalled: false, errors: false, pairing: false },
  incident: null, incidents: [], audit: [], tabs: {}, devMetricsOk: false, selRoute: null, selCheck: null,
  running: null, runLog: [], restore: { step: 0, pick: 0, target: 'scratch', dry: null }, flags: null, ack: {}, sort: {},
  savedViews: store.get('views', []), verifyRun: 0, supportCase: 0, familyFilter: 'all', routeFilter: '', deleteHold: 0,
};
const SECTIONS = [
  { g: 'Observe', items: [['overview', 'Overview', 'o'], ['health', 'Health', 'h'], ['requests', 'Requests', 'r'], ['jobs', 'Jobs & scheduler', 'j'], ['delivery', 'Delivery queue', 'd'], ['realtime', 'Realtime', 'w']] },
  { g: 'Data', items: [['database', 'Database', 'x'], ['backups', 'Backups & restore', 'b'], ['storage', 'Storage', 'm']] },
  { g: 'Trust', items: [['security', 'Security centre', 's'], ['audit', 'Audit log', 'a'], ['tenants', 'Tenants', 't']] },
  { g: 'Operate', items: [['flags', 'Flags & config', 'f'], ['incidents', 'Incidents', 'i'], ['capacity', 'Capacity & cost', 'c'], ['settings', 'Settings', 'e']] },
];
const FLAT = SECTIONS.flatMap((g) => g.items.map(([k, l, key]) => ({ k, l, key, g: g.g })));

// ---------------------------------------------------------------- formatting
const N = (v, d = 0) => Number(v).toLocaleString('en-US', { maximumFractionDigits: d, minimumFractionDigits: d });
const fms = (v) => v >= 1000 ? N(v / 1000, 2) + ' s' : (v < 10 ? N(v, 1) : N(v)) + ' ms';
const fdur = (s) => { s = Math.round(s); if (s < 60) return s + 's'; if (s < 3600) return Math.floor(s / 60) + 'm ' + (s % 60) + 's'; if (s < 86400) return Math.floor(s / 3600) + 'h ' + Math.floor(s % 3600 / 60) + 'm'; return Math.floor(s / 86400) + 'd ' + Math.floor(s % 86400 / 3600) + 'h'; };
const fgb = (g) => g >= 1000 ? N(g / 1000, 2) + ' TB' : g >= 1 ? N(g, 1) + ' GB' : N(g * 1024, 0) + ' MB';
const dstr = (t) => new Date(t).toISOString().slice(0, 10);
const tstr = (t) => new Date(t).toISOString().slice(0, 16).replace('T', ' ') + 'Z';
const agoS = (t) => fdur((Date.now() - t) / 1000) + ' ago';
const avg = (a) => a.reduce((x, y) => x + y, 0) / a.length;
const last = (a, k = 1) => a.slice(-k);
const nice = (v) => { if (v <= 0) return 1; const p = Math.pow(10, Math.floor(Math.log10(v))); const m = v / p; return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * p; };
const ic = (n, s = 16) => `<svg width="${s}" height="${s}" aria-hidden="true"><use href="#${n}"/></svg>`;
const ICON = { ok: 'i-ok', warn: 'i-warn', crit: 'i-crit', info: 'i-info', muted: 'i-prop' };
const st = (k, t) => `<span class="st ${k}">${ic(ICON[k] || 'i-info', 14)}${esc(t)}</span>`;
const SRC = { built: 'built', partial: 'partial', proposed: 'proposed' };
const src = (s, short) => `<span class="src src-${s}">${s === 'proposed' && !short ? 'proposed: not built yet' : SRC[s]}</span>`;
let uid = 0;

// ---------------------------------------------------------------- data access
let D = null;
function data() {
  D = O.build(state.env, state.range, state.faults);
  if (state.faults.errors) { const n = D.err5.length; for (let i = n - 6; i < n; i++) D.err5[i] += 1.4 + (i % 2) * .4; for (let i = n - 6; i < n; i++) { D.p95[i] += 160; D.p99[i] += 420; } }
  D.burn1 = avg(last(D.err5, Math.max(2, Math.round(D.err5.length / 24)))) / 0.1;
  D.burn6 = avg(last(D.err5, Math.max(6, Math.round(D.err5.length / 4)))) / 0.1;
  D.fam.list = O.families(state.env, state.faults);
  D.pending = state.env === 'prod' ? 2 : 0;
  D.hv = healthRows();
  return D;
}
function healthRows() {
  return O.HEALTH.map(([name, sev, meaning, from]) => {
    let observed = 0;
    if (name === 'stalled_delivery' && state.faults.stalled) observed = 3;
    return { name, sev, meaning, from, observed, threshold: 0, breach: observed > 0 };
  });
}
function healthCounts() { const b = D.hv.filter((r) => r.breach); return { total: D.hv.length, breach: b.length, crit: b.filter((r) => r.sev === 'critical').length }; }
function attention() {
  const out = [];
  D.hv.filter((r) => r.breach).forEach((r) => out.push({ k: r.sev === 'critical' ? 'crit' : 'warn', t: `health_check: ${r.name} = ${r.observed}`, to: 'health' }));
  if (state.faults.errors) out.push({ k: 'crit', t: `5xx burn rate ${N(D.burn1, 1)}x over the short window`, to: 'requests' });
  if (state.faults.pairing) out.push({ k: 'crit', t: 'Pairing-code miss rate above brute-force threshold', to: 'security' });
  if (D.P) {
    out.push({ k: 'warn', t: '2 migrations in repo not applied to prod (0037, 0038)', to: 'database' });
    out.push({ k: 'warn', t: 'Last restore drill 19 days ago; drills are not scheduled', to: 'backups' });
    out.push({ k: 'info', t: '2 deletion holds reach the 6-month minimum within 14 days', to: 'tenants' });
  } else out.push({ k: 'info', t: 'Scheduler profile is off in dev (by design)', to: 'jobs' });
  return out;
}

// ---------------------------------------------------------------- operator audit (session)
const h8 = (s) => { let h = 0x811c9dc5; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; } return h.toString(16).padStart(8, '0'); };
function seedAudit() {
  const base = Date.now(); const rows = [
    ['viewer.enter', 'tenants', 'support-case read, case c_91a2 consent verified', 'o.baker', 'responder', 3 * 3600e3],
    ['job.run', 'rematerialize', 'post-deploy sweep after 0036 migration', 'm.okafor', 'admin', 26 * 3600e3],
    ['config.view', 'secrets/validation', 'quarterly review', 'r.singh', 'auditor', 51 * 3600e3],
    ['alert.ack', 'backup_stale', 'cleared after manual run', 'o.baker', 'responder', 9 * 24 * 3600e3],
    ['token.create', 'tok_prom_scrape', 'prometheus scraper, scope metrics:read', 'm.okafor', 'admin', 12 * 24 * 3600e3],
  ];
  let prev = '00000000';
  rows.reverse().forEach(([action, target, reason, actor, role, ago], i) => { const t = base - ago; const hash = h8(prev + action + target + t); state.audit.push({ n: i + 1, t, actor, role, action, target, reason, prev, hash, seed: true }); prev = hash; });
  state.audit.reverse();
}
function logAction(action, target, reason) {
  const prev = state.audit[0] ? state.audit[0].hash : '00000000'; const t = Date.now();
  const e = { n: state.audit.length + 1, t, actor: 'm.okafor', role: 'admin', action, target, reason: reason || '-', prev, hash: h8(prev + action + target + t) };
  state.audit.unshift(e); return e;
}
function toast(msg, sub) { const el = document.createElement('div'); el.className = 'toast'; el.innerHTML = esc(msg) + (sub ? `<small>${esc(sub)}</small>` : ''); $('#toasts').append(el); setTimeout(() => el.remove(), 5200); }
function audited(action, target, reason, msg) { const e = logAction(action, target, reason); toast(msg || action, `recorded in operator audit log #A-${String(e.n).padStart(4, '0')} (${e.hash})`); }

// ---------------------------------------------------------------- components
function panel(o) {
  const id = 'p' + (++uid);
  return `<section class="card ${o.cls || ''}" aria-labelledby="${id}">
    <div class="card-h"><div><h2 id="${id}">${o.title}</h2>${o.sub ? `<p>${o.sub}</p>` : ''}</div><div class="row" style="flex:none">${o.actions || ''}</div></div>
    <div class="card-b">${o.body}</div>
    <div class="card-f">${src(o.status || 'proposed')}<span class="srcpath">${o.src || ''}</span>
      ${o.why ? `<details><summary>Why this panel exists</summary><p>${o.why}</p></details>` : ''}</div>
  </section>`;
}
function tile(o) {
  return `<div class="card tile ${o.warn ? 'is-warn' : ''} ${o.crit ? 'is-crit' : ''}">
    <div class="lbl"><span>${o.label}</span>${o.status ? src(o.status, true) : ''}</div>
    <div class="val">${o.value}${o.unit ? `<small>${o.unit}</small>` : ''}</div>
    <div class="sub">${o.sub || ''}</div>${o.spark ? `<div class="spark">${spark(o.spark, o.color)}</div>` : ''}
    ${o.src ? `<div class="srcpath" style="margin-top:6px">${o.src}</div>` : ''}</div>`;
}
function head(eyebrow, title, p, actions) { return `<div class="page-head"><div><div class="eyebrow">${eyebrow}</div><h1>${title}</h1>${p ? `<p>${p}</p>` : ''}</div><div class="actions">${actions || ''}</div></div>`; }
function notice(k, body) { return `<div class="notice ${k}">${ic(ICON[k] || 'i-info', 16)}<div>${body}</div></div>`; }
function empty(title, body, code) { return `<div class="empty"><h3>${title}</h3><p>${body}</p>${code ? `<pre style="text-align:left;margin-top:10px">${esc(code)}</pre>` : ''}</div>`; }
function tabs(name, items) {
  const cur = state.tabs[name] || items[0][0];
  return `<div class="tabs" role="tablist" aria-label="${name}">${items.map(([k, l]) => `<button role="tab" id="tab-${name}-${k}" aria-selected="${k === cur}" data-act="tab" data-n="${name}" data-k="${k}" data-fid="tab-${name}-${k}">${l}</button>`).join('')}</div>`;
}
const curTab = (name, def) => state.tabs[name] || def;

function spark(v, color = 'var(--c1)') {
  const mx = Math.max(...v, 1e-9); const mn = Math.min(...v, 0); const n = v.length;
  const pts = v.map((y, i) => `${(i / (n - 1) * 100).toFixed(1)},${(24 - (y - mn) / (mx - mn || 1) * 22 - 1).toFixed(1)}`).join(' ');
  return `<svg viewBox="0 0 100 24" preserveAspectRatio="none" aria-hidden="true"><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.6" vector-effect="non-scaling-stroke" stroke-linejoin="round"/></svg>`;
}

// Charts: SVG for geometry (non-scaling strokes), HTML for axis text so type never stretches.
const CH = {};
function line(id, o) {
  const all = o.series.flatMap((s) => s.v.filter((q) => q != null)).concat((o.thr || []).map((t) => t.v));
  const max = o.max || nice(Math.max(...all) * 1.08); const n = o.x.length; const h = o.h || 150;
  CH[id] = { ...o, max };
  const X = (i) => (i / (n - 1) * 100).toFixed(2); const Y = (v) => (100 - Math.min(v, max) / max * 100).toFixed(2);
  const grid = [0.25, 0.5, 0.75].map((f) => `<line x1="0" x2="100" y1="${f * 100}" y2="${f * 100}" stroke="var(--line)" stroke-width="1" vector-effect="non-scaling-stroke"/>`).join('');
  const body = o.series.map((s) => {
    const pts = s.v.map((v, i) => v == null ? null : `${X(i)},${Y(v)}`).filter(Boolean).join(' ');
    const area = o.area && s === o.series[0] ? `<polygon points="0,100 ${pts} 100,100" fill="${s.color}" opacity=".12"/>` : '';
    return `${area}<polyline points="${pts}" fill="none" stroke="${s.color}" stroke-width="2" ${s.dash ? 'stroke-dasharray="5 3"' : ''} vector-effect="non-scaling-stroke" stroke-linejoin="round"/>`;
  }).join('');
  const thr = (o.thr || []).map((t) => `<line x1="0" x2="100" y1="${Y(t.v)}" y2="${Y(t.v)}" stroke="var(--crit)" stroke-width="1.2" stroke-dasharray="4 3" vector-effect="non-scaling-stroke"/>`).join('');
  const thrL = (o.thr || []).map((t) => `<span class="thr-label" style="top:${Y(t.v)}%">${esc(t.label)}</span>`).join('');
  const fy = o.fmt || ((v) => N(v, v < 10 ? 1 : 0));
  const yl = [1, .66, .33, 0].map((f) => `<span>${fy(max * f)}</span>`).join('');
  const xl = [0, .25, .5, .75, 1].map((f) => `<span>${O.fmtTime(o.x[Math.round(f * (n - 1))], state.range)}</span>`).join('');
  const summary = o.series.map((s) => { const v = s.v.filter((q) => q != null); return `${s.name} latest ${fy(v[v.length - 1])}, peak ${fy(Math.max(...v))}`; }).join('; ');
  return `<figure class="chart" data-chart="${id}">
    <div class="chart-body"><div class="yaxis" aria-hidden="true" style="height:${h}px">${yl}</div>
      <div class="plot" style="--h:${h}px" tabindex="0" role="img" aria-label="${esc((o.title || id) + '. ' + summary + '. Use left and right arrow keys to read values.')}" data-chart="${id}">
        <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">${grid}${thr}${body}</svg>${thrL}
        <div class="cursor"></div><div class="tip"></div></div></div>
    <div class="xaxis" aria-hidden="true">${xl}</div>
    <figcaption class="legend">${o.series.map((s) => `<span><i class="sw ${s.dash ? 'dash' : ''}" style="border-color:${s.color}"></i>${esc(s.name)}</span>`).join('')}</figcaption></figure>`;
}
function moveCursor(plot, i) {
  const c = CH[plot.dataset.chart]; if (!c) return; const n = c.x.length; i = Math.max(0, Math.min(n - 1, i));
  const pct = i / (n - 1) * 100; plot.classList.add('on'); plot.querySelector('.cursor').style.left = pct + '%';
  const tip = plot.querySelector('.tip'); const fy = c.fmt || ((v) => N(v, v < 10 ? 1 : 0));
  tip.innerHTML = `<b>${O.fmtTime(c.x[i], state.range)} UTC</b>` + c.series.map((s) => `<span><em style="font-style:normal"><i style="background:${s.color}"></i>${esc(s.name)}</em><strong>${s.v[i] == null ? '-' : fy(s.v[i]) + (c.unit || '')}</strong></span>`).join('');
  tip.style.left = pct > 60 ? 'auto' : `calc(${pct}% + 10px)`; tip.style.right = pct > 60 ? `calc(${100 - pct}% + 10px)` : 'auto';
  plot.dataset.idx = i;
}
function bars(vals, o = {}) {
  const mx = Math.max(...vals.map((v) => v.n ?? v), 1);
  return `<div class="bars" style="--h:${o.h || 110}px" role="img" aria-label="${esc(o.label || 'bar chart')}: ${vals.map((v, i) => `${(o.names || [])[i] || i} ${v.n ?? v}`).join(', ')}">${vals.map((v, i) => { const n = v.n ?? v; return `<div class="${v.cls || ''}" style="height:${Math.max(n / mx * 100, n > 0 ? 2 : 0)}%" title="${esc((o.names || [])[i] || '')} ${N(n)}"></div>`; }).join('')}</div>
  ${o.names ? `<div class="bars-x" aria-hidden="true">${o.names.map((nm) => `<span>${esc(nm)}</span>`).join('')}</div>` : ''}`;
}

// Sortable table
const TB = {};
function table(id, cols, rows, o = {}) {
  TB[id] = { cols, rows, o };
  return `<div class="tw" id="tw-${id}">${tableInner(id)}</div>`;
}
function tableInner(id) {
  const { cols, rows, o } = TB[id]; const s = state.sort[id] || o.sort || null;
  let r = rows.slice();
  if (s) { const c = cols.find((c) => c.k === s.k); const val = (x) => c.v ? c.v(x) : x[c.k]; r.sort((a, b) => { const A = val(a), B = val(b); return (A > B ? 1 : A < B ? -1 : 0) * (s.dir === 'desc' ? -1 : 1); }); }
  if (o.filter) r = r.filter(o.filter);
  if (!r.length) return empty(o.emptyTitle || 'Nothing to show', o.emptyBody || 'No rows match this view.');
  return `<table><caption class="sr">${esc(o.caption || id)}</caption><thead><tr>${cols.map((c) => {
    const act = s && s.k === c.k; const sort = act ? (s.dir === 'desc' ? 'descending' : 'ascending') : 'none';
    return `<th scope="col" class="${c.num ? 'num' : ''}" aria-sort="${sort}">${c.nosort ? esc(c.label) : `<button data-act="sort" data-t="${id}" data-k="${c.k}" data-fid="th-${id}-${c.k}">${esc(c.label)}<span aria-hidden="true">${act ? (s.dir === 'desc' ? '▾' : '▴') : ''}</span></button>`}</th>`;
  }).join('')}</tr></thead><tbody>${r.map((x) => `<tr ${o.rowAttr ? o.rowAttr(x) : ''}>${cols.map((c) => `<td class="${c.num ? 'num' : ''} ${c.mono ? 'mono' : ''}">${c.f ? c.f(x) : esc(x[c.k])}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
}

// ---------------------------------------------------------------- views
const V = {};

V.overview = () => {
  const P = D.P; const hc = healthCounts(); const att = attention();
  const avail = P ? 99.94 - (state.faults.errors ? .31 : 0) : 99.99; const budget = Math.max(0, Math.round((1 - (100 - avail) / 0.1) * 100));
  const meterPct = Math.min(D.burn1 / 15 * 100, 100);
  const bcls = D.burn1 >= 6 ? 'crit' : D.burn1 >= 1 ? 'warn' : '';
  const latOk = P ? 99.2 : 99.9;
  const states = D.del;
  return head(`Overview &middot; ${state.env} &middot; ${O.RANGES[state.range].label}`, 'Is Olive healthy right now?',
      'The operator view is aggregate by design: counts, states, timings. No family, child, message or media is ever shown here.',
      `<button class="btn" data-act="goto" data-to="health">${hc.breach ? st('crit', hc.breach + ' check breached') : st('ok', 'All ' + hc.total + ' checks clear')}</button>`) +
    `<div class="grid">
      ${tile({ label: 'Availability, 30 d', value: N(avail, 2), unit: '%', sub: `SLO 99.9% &middot; error budget left ${budget}%`, status: 'proposed', src: 'SLO calc: no store of history yet; /healthz is built', warn: budget < 40 }).replace('class="card', 'class="s3 card')}
      <div class="s3 card tile ${bcls ? 'is-' + bcls : ''}"><div class="lbl"><span>5xx burn rate</span>${src('proposed', true)}</div>
        <div class="val">${N(D.burn1, 1)}<small>x short &middot; ${N(D.burn6, 1)}x long</small></div>
        <div class="meter" role="meter" aria-valuemin="0" aria-valuemax="15" aria-valuenow="${N(D.burn1, 1)}" aria-label="Burn rate"><i class="${bcls}" style="width:${meterPct}%"></i></div>
        <div class="meter-ticks" aria-hidden="true"><span style="left:6.7%">1x</span><span style="left:40%">6x</span><span style="left:96%">14.4x</span></div>
        <div class="sub">Page at 14.4x (1 h) and 6x (6 h) of a 0.1% budget</div></div>
      ${tile({ label: 'Latency SLO, p95 &lt; 150 ms', value: N(latOk, 1), unit: '%', sub: 'ms_avg / ms_max exist today; percentiles do not', status: 'proposed', src: 'needs histogram buckets in Metrics.record()' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Delivery freshness SLO', value: 'no data', sub: 'ready &rarr; delivered &lt; 2 min cannot be measured: no delivery worker', status: 'proposed', src: 'claim_due_intents() has no caller (docs/scheduler.md)', warn: true }).replace('class="card', 'class="s3 card')}
    </div>
    <div class="grid">
      <div class="s8">${panel({ title: 'Request rate', sub: `${N(D.total)} requests in range &middot; avg ${N(D.avgRps, 2)} rps`, status: 'partial', src: 'server/observability.mjs: Metrics.requests (counter only); time series = proposed',
        why: '/internal/metrics gives a cumulative counter since process start. A rate over time needs a scraper or a ring buffer; neither exists.',
        body: line('rps', { title: 'Requests per second', x: D.x, series: [{ name: 'requests / s', v: D.rps, color: 'var(--c2)' }], area: true, fmt: (v) => N(v, 2), unit: ' rps' }) })}</div>
      <div class="s4">${panel({ title: 'Active families', sub: 'distinct families with a session in range (count only)', status: 'proposed', src: 'derive from session table; not exposed',
        why: 'Capacity and cost per family start here. Family ids never leave the database in clear: this is a COUNT(DISTINCT).',
        body: `<dl class="kv"><dt>Active, 24 h</dt><dd><strong>${D.fam.a24}</strong></dd><dt>Active, 7 d</dt><dd>${D.fam.a7}</dd><dt>Total families</dt><dd>${D.fam.total}</dd><dt>Children (count)</dt><dd>${D.fam.kids}</dd><dt>Guardians (count)</dt><dd>${D.fam.guardians}</dd></dl>
        <div class="stack" style="margin-top:12px" aria-hidden="true"><i style="width:${D.fam.a24 / D.fam.total * 100}%;background:var(--c1)"></i><i style="width:${(D.fam.a7 - D.fam.a24) / D.fam.total * 100}%;background:var(--c2)"></i></div>
        <div class="legend"><span><i class="sw" style="border-color:var(--c1)"></i>24 h</span><span><i class="sw" style="border-color:var(--c2)"></i>7 d only</span></div>` })}</div>
    </div>
    <div class="grid">
      <div class="s6">${panel({ title: 'Latency percentiles', sub: 'all routes, server-side ms', status: 'proposed', src: 'today: ms_avg + ms_max per route in /internal/metrics',
        why: 'Averages hide the tail. The access log already carries ms per request, so percentiles can be built from logs with no new instrumentation.',
        body: line('lat', { title: 'Latency percentiles', x: D.x, series: [{ name: 'p50', v: D.p50, color: 'var(--c1)' }, { name: 'p95', v: D.p95, color: 'var(--c3)' }, { name: 'p99', v: D.p99, color: 'var(--c4)', dash: true }], fmt: (v) => N(v), unit: ' ms', thr: [{ v: 150, label: 'SLO 150 ms (p95)' }] }) })}</div>
      <div class="s6">${panel({ title: 'Error rate', sub: '5xx and 4xx as % of requests', status: 'partial', src: 'by_status_class in /internal/metrics is built (cumulative)',
        why: 'by_status_class and per-route errors_5xx are counted today. The 0.1% line is the error budget behind the burn-rate tile.',
        body: line('err', { title: 'Error rate', x: D.x, series: [{ name: '5xx %', v: D.err5, color: 'var(--crit)' }, { name: '4xx %', v: D.err4, color: 'var(--c2)', dash: true }], fmt: (v) => N(v, 2), unit: '%', thr: [{ v: 0.1, label: 'budget 0.1%' }] }) })}</div>
    </div>
    <div class="grid">
      <div class="s4">${panel({ title: 'Queue health', sub: 'delivery_intent by state, now', status: 'partial', src: 'delivery_intent.state CHECK in 0001_phase0_init.sql',
        why: 'The product promise is that a message arrives when the child can receive it. Queue shape is the earliest signal that promise is slipping.',
        body: `<div class="stack" role="img" aria-label="Queue states" style="height:22px"><i style="width:${states.pending / (states.pending + states.ready + 1) * 100}%;background:var(--c3)"></i><i style="width:${states.ready / (states.pending + states.ready + 1) * 100}%;background:${state.faults.stalled ? 'var(--crit)' : 'var(--c2)'}"></i></div>
        <dl class="kv" style="margin-top:10px"><dt>pending</dt><dd>${states.pending}</dd><dt>ready</dt><dd>${states.ready}</dd><dt>oldest ready</dt><dd>${state.faults.stalled ? st('crit', fdur(D.oldestReady)) : fdur(D.oldestReady)}</dd></dl>` })}</div>
      <div class="s4">${panel({ title: 'Scheduled jobs', sub: 'last run per job', status: 'partial', src: 'tools/scheduler.mjs log lines (no run table)',
        why: 'Delivery depends on rematerialize running nightly. Run state is only in logs today, so the console needs a job_run table (proposed).',
        body: `<ul style="list-style:none;margin:0;padding:0;display:grid;gap:7px">${D.jobs.filter((j) => j.built).map((j) => `<li class="row" style="justify-content:space-between"><span class="mono">${j.name}</span>${P ? st(j.last.s === 'ok' ? 'ok' : j.last.s === 'skip' ? 'muted' : 'warn', j.last.s === 'ok' ? 'ok' : j.last.s) : st('muted', 'not started')}</li>`).join('')}</ul>` })}</div>
      <div class="s4">${panel({ title: 'Needs attention', sub: `${att.length} items, ranked`, status: 'proposed', src: 'composed in the console from the panels linked',
        why: 'One place to start a shift. Each row links to the panel that owns the evidence.',
        body: `<ul style="list-style:none;margin:0;padding:0;display:grid;gap:9px">${att.map((a) => `<li>${st(a.k, '')}<a href="#/${a.to}" style="margin-left:2px">${esc(a.t)}</a></li>`).join('')}</ul>` })}</div>
    </div>`;
};

V.health = () => {
  const hc = healthCounts();
  const rows = D.hv.map((r) => ({ ...r, kind: r.breach ? (r.sev === 'critical' ? 'crit' : 'warn') : 'ok' }));
  const hist = (nm) => O.series(nm.length * 31, 14, (i, r) => (state.faults.stalled && nm === 'stalled_delivery' && i > 10 ? 1 + i - 10 : 0));
  const board = rows.map((r) => `<button class="check ${r.kind}" style="text-align:left;font:inherit;color:inherit;cursor:pointer" data-act="check" data-k="${r.name}" data-fid="chk-${r.name}">
      <div class="row" style="justify-content:space-between"><span class="nm">${r.name}</span>${st(r.kind, r.kind === 'ok' ? 'ok' : r.kind === 'crit' ? 'critical' : 'breach')}</div>
      <div class="ob">${r.observed}<small> observed &middot; threshold ${r.threshold}</small></div><p>${esc(r.meaning)}</p><div class="spark">${spark(hist(r.name), r.breach ? 'var(--crit)' : 'var(--ok)')}</div></button>`).join('');
  const bk = D.P ? { observed: 0, threshold: 36, text: 'newest dump 7 h old', kind: 'ok' } : null;
  const extra = [
    ['backup_stale', 'built', bk ? `${bk.text} (limit ${bk.threshold} h)` : 'inactive: BACKUP_DIR unset in dev, so no backups were ever promised', bk ? 'ok' : 'muted', 'tools/health-alert.mjs staleBackupAlarm(); not a row of the view'],
    ['oldest_ready_age', 'proposed', state.faults.stalled ? `74 min, over the 15 min line` : `${fdur(D.oldestReady)}, under the 15 min line`, state.faults.stalled ? 'crit' : 'ok', 'MIN(now() - scheduled_at) over state=\'ready\'. stalled_delivery only counts after 1 h.'],
    ['rls_catalog_coverage', 'proposed', `${O.TRACKED.length} of ${O.TRACKED.length + 14} public tables on the hand-kept list`, 'warn', 'rls_unforced checks a fixed 25-name list; a new table is invisible until someone edits the view.'],
    ['hash_chain_verify', 'partial', 'verifyChain() exists in packages/ledger; no scheduled per-family run', 'info', 'log_sequence_gap catches missing seq, not a rewritten hash.'],
    ['migration_drift', 'partial', D.P ? '2 repo migrations unapplied' : 'in sync', D.P ? 'warn' : 'ok', 'tools/migrate.mjs compares checksums against schema_migration.'],
  ];
  return head(`Health &middot; ${state.env}`, 'health_check, as a live board',
      'One view is the canonical alerting source (0009). Today it is read by tools/health-alert.mjs, which detects and exits non-zero; nothing pages anyone.',
      `<span class="chip"><span class="dot-live"></span>checked <span data-live="age" data-t="${Date.now()}">0s</span> ago</span><button class="btn" data-act="recheck">Re-run now</button>`) +
    `<div class="grid"><div class="s12 notice ${hc.breach ? 'crit' : 'info'}" style="display:flex">${ic(hc.breach ? 'i-crit' : 'i-ok')}<div><strong>${hc.total - hc.breach} of ${hc.total}</strong> view checks within threshold${hc.breach ? `; <strong>${hc.breach} breached</strong>` : ''}. A breach is <code>observed &gt; threshold</code>; severity comes from the view (critical or high).</div></div></div>
    <div class="grid"><div class="s12">${panel({ title: 'health_check view', sub: 'one row per check; click a check for evidence and runbook', status: 'built', src: 'db/migrations/0029_rls_coverage_fix.sql (latest definition); db/migrations/0009 documents it',
        why: 'These eight checks are the existing contract. Everything else on this page is labelled partial or proposed.', body: `<div class="board">${board}</div>` })}</div></div>
    <div class="grid"><div class="s8">${panel({ title: 'Beyond the view', sub: 'checks the operator asked for, with honest build status', status: 'partial', src: 'tools/health-alert.mjs, tools/migrate.mjs, packages/ledger',
        body: `<div class="tw">${table('extra', [{ k: 'n', label: 'Check', mono: true, f: (r) => r.n }, { k: 's', label: 'Backing', f: (r) => src(r.s) }, { k: 'r', label: 'State now', f: (r) => st(r.kind, r.r) }, { k: 'w', label: 'Note', nosort: true, f: (r) => `<span style="color:var(--ink-2)">${esc(r.w)}</span>` }], extra.map(([n, s, r, kind, w]) => ({ n, s, r, kind, w })), { caption: 'Extra checks' })}</div>` })}</div>
      <div class="s4">${panel({ title: 'Sample fault injector', sub: 'demo only: shows how the console reacts', status: 'proposed', src: 'not part of the product; mockup control',
        body: `<div class="row" style="flex-direction:column;align-items:stretch">
          <button class="btn" data-act="fault" data-k="stalled" aria-pressed="${state.faults.stalled}">${state.faults.stalled ? 'Clear' : 'Inject'}: stalled delivery</button>
          <button class="btn" data-act="fault" data-k="errors" aria-pressed="${state.faults.errors}">${state.faults.errors ? 'Clear' : 'Inject'}: 5xx spike</button>
          <button class="btn" data-act="fault" data-k="pairing" aria-pressed="${state.faults.pairing}">${state.faults.pairing ? 'Clear' : 'Inject'}: pairing brute force</button></div>` })}</div></div>`;
};

V.requests = () => {
  if (!D.P && !state.devMetricsOk) {
    return head('Requests &middot; dev', 'Routes and latency', 'Per-route volume, errors, rate-limit hits and latency.') +
      panel({ title: 'Metrics scrape failed', status: 'built', src: 'server/observability.mjs: isInternalRequest(); GET /internal/metrics', cls: 's12',
        why: 'This is the real failure mode: /internal/metrics answers 404 to anything that is not loopback with no proxy headers, or lacks x-internal-token. It hides its own existence.',
        body: notice('crit', `<strong>GET /internal/metrics &rarr; 404 not_found</strong><br>The console runs on another host, so loopback does not match. A refused caller gets the same 404 an unknown path would.`) +
          `<pre style="margin:12px 0">INTERNAL_METRICS_TOKEN=&lt;set on the server&gt;
curl -H "x-internal-token: $TOKEN" http://server:3000/internal/metrics</pre><button class="btn primary" data-act="devtoken">Use sample token and retry</button>` });
  }
  const f = state.routeFilter.toLowerCase();
  const sel = state.selRoute != null ? D.routes[state.selRoute] : null;
  const tot = D.routes.reduce((a, r) => a + r.count, 0); const e5 = D.routes.reduce((a, r) => a + r.count * r.e5 / 100, 0);
  const cols = [
    { k: 'r', label: 'Route', f: (r) => `<button class="row-btn" data-act="route" data-i="${r.i}" data-fid="rt-${r.i}"><span style="color:var(--ink-3)">${r.m}</span> ${esc(r.r)}</button>` },
    { k: 'count', label: 'Requests', num: true, f: (r) => N(r.count) }, { k: 'rps', label: 'rps', num: true, f: (r) => N(r.rps, 2) },
    { k: 'p50', label: 'p50', num: true, f: (r) => fms(r.p50) }, { k: 'p95', label: 'p95', num: true, f: (r) => fms(r.p95) }, { k: 'p99', label: 'p99', num: true, f: (r) => fms(r.p99) },
    { k: 'e4', label: '4xx', num: true, f: (r) => N(r.e4, 1) + '%' }, { k: 'e5', label: '5xx', num: true, f: (r) => r.e5 > .2 ? st('crit', N(r.e5, 2) + '%') : N(r.e5, 2) + '%' },
    { k: 'rl', label: 'Rate-limited', num: true, f: (r) => N(r.rl) },
    { k: 'spark', label: '24 h', nosort: true, f: (r) => `<div class="spark" style="width:72px">${spark(r.spark)}</div>` },
  ];
  let detail = '';
  if (sel) {
    const bins = O.histBins(sel.p50, sel.p95, sel.count);
    const names = bins.map((b) => b.hi === Infinity ? '2k+' : b.hi >= 1000 ? b.hi / 1000 + 's' : b.hi);
    const rr = O.rng(sel.i * 99 + 3); const rows = Array.from({ length: 10 }, (_, i) => { const code = rr() < .9 ? (sel.m === 'POST' && rr() < .5 ? 201 : 200) : (rr() < .5 ? 429 : (rr() < .5 ? 401 : 500)); return { id: O.hex(rr, 8) + '…', t: Date.now() - Math.round((i * 7 + rr() * 6) * 1000), code, ms: Math.round(sel.p50 * (.5 + rr() * (code >= 500 ? 9 : 2))) }; });
    const series = O.series(sel.i + 5, D.x.length, (i, r) => sel.p95 * (.8 + .4 * O.wave(D.x[i]) + r() * .15));
    detail = `<div class="grid"><div class="s12">${panel({ title: `<span class="mono">${sel.m} ${esc(sel.r)}</span>`, sub: esc(sel.note) + ' &middot; route template only; concrete URLs and ids never reach the log', status: 'partial', src: 'built: count, errors_5xx, ms_avg, ms_max, access log {ts,id,method,route,status,ms}. proposed: histogram, p-values, 4xx by route, log viewer.',
      actions: '<button class="btn sm" data-act="route" data-i="">Close</button>',
      why: 'Per-route detail answers "is this one route slow or is everything slow". The recent-id list lets an operator correlate with a request id a user quotes, without ever seeing the URL parameters.',
      body: `<div class="grid" style="margin:0"><div class="s5"><h3>Latency distribution</h3><p style="color:var(--ink-3);font-size:12px;margin-bottom:8px">log-spaced ms buckets, ${N(sel.count)} requests (modelled from p50/p95)</p>${bars(bins, { names, h: 130, label: 'Latency histogram' })}</div>
        <div class="s4"><h3>p95 over time</h3>${line('rt95', { title: 'p95', x: D.x, series: [{ name: 'p95', v: series, color: 'var(--c3)' }], h: 130, fmt: (v) => N(v), unit: ' ms' })}</div>
        <div class="s3"><h3>Recent requests</h3>${table('recent', [{ k: 'id', label: 'x-request-id', mono: true, nosort: true, f: (x) => x.id }, { k: 'code', label: 'Status', nosort: true, f: (x) => st(x.code >= 500 ? 'crit' : x.code >= 400 ? 'warn' : 'ok', x.code) }, { k: 'ms', label: 'ms', num: true, nosort: true, f: (x) => x.ms }], rows, { caption: 'Recent requests' })}</div></div>` })}</div></div>`;
  }
  return head(`Requests &middot; ${state.env} &middot; ${O.RANGES[state.range].label}`, 'Routes and latency', 'Per-route volume, errors, rate-limit hits and latency. Rows are route templates, never concrete URLs.',
      `<label class="sel" style="width:220px"><span class="sr">Filter routes</span>${ic('i-search', 14)}<input id="routeFilter" type="search" placeholder="Filter routes" value="${esc(state.routeFilter)}" style="border:0;background:transparent;outline:0;width:100%;height:100%;color:inherit"></label>`) +
    `<div class="grid">
      ${tile({ label: 'Requests', value: N(tot), sub: `${N(D.avgRps, 2)} rps average`, status: 'partial', src: 'requests_total (cumulative)' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'p95 latency', value: fms(Math.round(avg(last(D.p95, 6)))), sub: 'all routes, last few buckets', status: 'proposed' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: '5xx rate', value: N(e5 / tot * 100, 2), unit: '%', sub: 'errors_5xx / count', status: 'built', src: 'routes[*].errors_5xx', crit: state.faults.errors }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Rate-limited', value: N(D.routes.reduce((a, r) => a + r.rl, 0)), sub: 'counter: rate_limited_total', status: 'built', src: 'metrics.inc(\'rate_limited_total\')' }).replace('class="card', 'class="s3 card')}
    </div>
    <div class="grid"><div class="s12">${panel({ title: 'Routes', sub: 'click a route for its histogram and recent request ids', status: 'partial', src: 'server/observability.mjs Metrics.snapshot().routes (bounded to 500 keys)',
      why: 'Routes are the unit of ownership and of SLOs. The map is capped at 500 keys so a bug cannot become an unbounded cardinality problem; the console inherits that guarantee.',
      body: table('routes', cols, D.routes, { sort: { k: 'count', dir: 'desc' }, caption: 'Routes', filter: (r) => !f || (r.m + ' ' + r.r).toLowerCase().includes(f) }) })}</div></div>${detail}
    <div class="grid"><div class="s12">${notice('info', '<strong>What exists vs what is proposed.</strong> Built: per-route <code>count</code>, <code>errors_5xx</code>, <code>ms_avg</code>, <code>ms_max</code>, the JSON access log line, and the <code>x-request-id</code> echo. Proposed: p50/p95/p99, 4xx by route, per-route rate-limit hits (today a single global counter), time series (counters reset on restart), and a log search. The columns above that need these are sample values.')}</div></div>`;
};

function nextRun() { const d = new Date(); d.setUTCHours(3, 0, 0, 0); if (d <= new Date()) d.setUTCDate(d.getUTCDate() + 1); return d.getTime(); }
V.jobs = () => {
  const P = D.P; const sel = state.selJob;
  const cols = [
    { k: 'name', label: 'Job', f: (j) => `<span class="mono"><strong>${j.name}</strong></span><br><span style="color:var(--ink-3);font-size:12px">${esc(j.every)}</span>` },
    { k: 's', label: 'Status', v: (j) => j.last.s, f: (j) => !j.built ? src('proposed') : !P ? st('muted', j.name === 'backup' ? 'skipped: not_configured' : 'scheduler profile off') : st(j.last.s === 'ok' ? 'ok' : j.last.s === 'warn' ? 'warn' : j.last.s === 'crit' ? 'crit' : 'muted', j.last.s === 'ok' ? 'ok' : j.last.s === 'warn' ? 'breach / skipped lock' : j.last.s === 'crit' ? 'failed' : 'none') },
    { k: 'lastRun', label: 'Last run', f: (j) => !j.built || !P ? '-' : `<span class="mono">03:00:0${j.name.length % 9}Z</span><br><span style="color:var(--ink-3);font-size:12px">${agoS(new Date().setUTCHours(3, 0, 0, 0) - (new Date().getUTCHours() < 3 ? 86400000 : 0))}</span>` },
    { k: 'dur', label: 'Duration', num: true, v: (j) => j.last.dur, f: (j) => j.built && P ? fms(j.last.dur) : '-' },
    { k: 'lock', label: 'Lock holder', nosort: true, f: (j) => !j.built ? '-' : state.running === j.name ? '<span class="chip warn">held by manual run (you)</span>' : '<span style="color:var(--ink-3)">free</span>' },
    { k: 'next', label: 'Next run', nosort: true, f: (j) => !j.built ? '-' : !P ? 'not scheduled' : `<span class="mono">${tstr(j.name === 'health-alert' ? nextRun() + 61000 : nextRun())}</span>` },
    { k: 'act', label: '', nosort: true, f: (j) => !j.built ? `<button class="btn sm" disabled>Run</button>` : `<button class="btn sm" data-act="runjob" data-j="${j.name}" data-fid="run-${j.name}" ${state.running ? 'disabled' : ''}>${ic('i-play', 12)}Run now</button>` },
  ];
  const selH = sel ? D.jobs.find((j) => j.name === sel.j)?.hist[sel.d] : null;
  const cells = D.jobs.filter((j) => j.built).map((j) => `<span class="rl">${j.name}</span>${j.hist.map((h) => `<button class="cell ${h.s === 'ok' ? '' : h.s}" aria-pressed="${sel && sel.j === j.name && sel.d === h.d}" aria-label="${j.name}, ${13 - h.d} days ago, ${h.s === 'none' ? 'no run' : h.s}" data-act="cell" data-j="${j.name}" data-d="${h.d}"></button>`).join('')}`).join('');
  const logs = D.P ? D.jobs.filter((j) => j.built).map((j, i) => `<span class="k">scope=scheduler event=start job=${j.name} at=${new Date().toISOString().slice(0, 11)}03:00:0${i}.0${i}0Z</span>\nscope=scheduler event=end job=${j.name} status=${j.last.s === 'ok' ? '<span class="g">ok</span>' : '<span class="w">' + (j.last.s === 'crit' ? 'failed' : 'breach') + '</span>'} duration_ms=${j.last.dur} ${esc(j.fieldsStr)}`).join('\n') : '(no scheduler output: the scheduler service is behind a Compose profile in dev)';
  return head(`Jobs &middot; ${state.env}`, 'Jobs and scheduler', 'tools/scheduler.mjs runs five named jobs behind a Postgres advisory lock per job. Run state lives in logs only; this page shows what a run table would give you.',
      `<span class="chip">${ic('i-clock', 12)}next sweep ${tstr(nextRun())}</span>`) +
    (P ? '' : `<div class="grid"><div class="s12">${notice('info', '<strong>Scheduler profile is off in dev</strong> (deliberately: it would rewrite delivery_intent rows mid-debug). <code>docker compose -f docker-compose.dev.yml --profile scheduler up -d --build</code>')}</div></div>`) +
    `<div class="grid"><div class="s12">${panel({ title: 'Jobs', sub: 'five built jobs, one planned', status: 'partial', src: 'tools/scheduler.mjs (JOB_NAMES, pg_try_advisory_lock). Run history, duration and lock holder here need a job_run table: proposed.',
      why: 'The scheduler is the only thing that moves a message from pending to ready. If it silently stops, nothing is delivered. The delivery-worker row is planned, not built: claim_due_intents() has no caller.',
      body: table('jobs', cols, D.jobs, { caption: 'Scheduled jobs' }) })}</div></div>
    <div class="grid"><div class="s8">${panel({ title: 'Run history, 14 days', sub: 'one cell per daily run; select a cell for the log line', status: 'proposed', src: 'derive from structured scheduler log lines; no table yet',
      body: `<div class="tw"><div class="cells" role="group" aria-label="Run history">${cells}</div></div>
        <p id="runDetail" style="margin-top:10px;font:400 12px var(--font-mono);color:var(--ink-2);min-height:20px" aria-live="polite">${selH ? `${sel.j}: ${13 - sel.d} d ago, ${selH.s}, ${fms(selH.dur)}` : 'Select a cell.'}</p>
        <div class="legend"><span>${st('ok', 'ok')}</span><span>${st('warn', 'breach / lock contention')}</span><span>${st('crit', 'failed')}</span><span>${st('muted', 'skipped / none')}</span></div>` })}</div>
      <div class="s4">${panel({ title: 'Last output', sub: 'real log shape: flat key=value', status: 'built', src: 'docs/scheduler.md "Reading its logs"', body: `<pre aria-label="scheduler log">${logs}</pre>` })}</div></div>
    ${state.runLog.length ? `<div class="grid"><div class="s12">${panel({ title: 'Manual run output', sub: 'this session', status: 'proposed', src: 'console would shell to `node tools/scheduler.mjs run <job>` under the same advisory lock', body: `<pre aria-live="polite">${state.runLog.join('\n')}</pre>` })}</div></div>` : ''}`;
};

V.delivery = () => {
  const d = D.del; const fl = state.faults.stalled;
  const node = (l, n, cls = '', note = '') => `<div class="node ${cls}"><div class="n">${n == null ? '-' : N(n)}</div><div class="l">${l}</div>${note ? `<div style="font-size:11px;color:var(--ink-3)">${note}</div>` : ''}</div>`;
  const a = D.ageBuckets;
  return head(`Delivery queue &middot; ${state.env}`, 'Intents by state, age and lease', 'Rows are delivery_intent states. The console sees state, age and attempt counts, never sender names, recipients, content or media.') +
    `<div class="grid"><div class="s12">${panel({ title: 'Lifecycle', sub: 'counts now; dashed = not in the schema today', status: 'partial', src: "db/migrations/0001_phase0_init.sql: state IN ('pending','ready','delivered','opened','expired','revoked')",
      why: 'There is no delivering state: claim_due_intents() (0002) claims ready rows but nothing calls it. The console shows delivering as proposed so nobody assumes it exists.',
      body: `<div class="flow">${node('pending', d.pending)}<span class="arrow" aria-hidden="true">&rarr;</span>${node('ready', d.ready, '', fl ? 'stalled' : '')}<span class="arrow" aria-hidden="true">&rarr;</span>${node('delivering', null, 'prop', 'proposed')}<span class="arrow" aria-hidden="true">&rarr;</span>${node('delivered', d.delivered)}<span class="arrow" aria-hidden="true">&rarr;</span>${node('opened', d.opened)}<span style="flex-basis:100%"></span>${node('expired', d.expired)}${node('revoked', d.revoked)}</div>` })}</div></div>
    <div class="grid">
      ${tile({ label: 'Oldest ready intent', value: fdur(D.oldestReady), sub: fl ? 'over the 1 h stalled_delivery line' : 'healthy: sweep is current', status: 'proposed', src: 'MIN(now() - scheduled_at)', crit: fl }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Unmaterialized', value: '0', sub: "pending with scheduled_at NULL > 1 h", status: 'built', src: 'health_check.unmaterialized' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Orphan risk', value: '0', sub: 'media expires before delivery', status: 'built', src: 'view orphan_risk (0005)' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Stalled delivery', value: fl ? '3' : '0', sub: "ready and scheduled_at &lt; now()-1h", status: 'built', src: 'health_check.stalled_delivery', crit: fl }).replace('class="card', 'class="s3 card')}
    </div>
    <div class="grid"><div class="s6">${panel({ title: 'Age buckets', sub: 'time since scheduled_at (ready) or created_at (pending)', status: 'proposed', src: 'GROUP BY width_bucket(extract(epoch from now()-ts)); aggregate only',
      body: `<div class="split"><div><h3>Pending</h3>${bars(a.map((r) => r[1]), { names: a.map((r) => r[0]), h: 100, label: 'Pending age' })}</div><div><h3>Ready</h3>${bars(a.map((r, i) => ({ n: r[2], cls: fl && i > 2 ? 'bad' : '' })), { names: a.map((r) => r[0]), h: 100, label: 'Ready age' })}</div></div>` })}</div>
      <div class="s6">${panel({ title: 'Lease and attempt view', sub: 'sample rows; ids truncated, no content', status: 'proposed', src: 'delivery_intent has no lease or attempt columns today; claim_due_intents() is SQL-only',
        why: 'Once a worker exists, an operator needs to know whether an intent is stuck because it is leased to a dead worker or because it keeps failing. Both need new columns.',
        body: table('lease', [{ k: 'id', label: 'Intent', mono: true, f: (r) => r.id + '…' }, { k: 'state', label: 'State', f: (r) => `<span class="chip">${r.state}</span>` }, { k: 'age', label: 'Age', num: true, f: (r) => fdur(r.age) }, { k: 'attempts', label: 'Attempts', num: true, f: (r) => r.attempts > 1 ? st('warn', r.attempts) : r.attempts }, { k: 'lease', label: 'Lease', f: (r) => r.lease ? `<span class="mono">${r.lease}</span> <span style="color:var(--ink-3)">${r.leaseTtl}s</span>` : '<span style="color:var(--ink-3)">none</span>' }, { k: 'tz', label: 'Child tz', f: (r) => `<span class="mono">${r.tz.split('/')[0]}</span>` }], D.leases, { sort: { k: 'age', dir: 'desc' }, caption: 'Leases' }) })}</div></div>
    <div class="grid"><div class="s12">${notice('warn', '<strong>No delivery worker today.</strong> The scheduler makes intents reach <code>ready</code>; nothing yet claims them. expire_stale_intents() (COPPA retention expiry) and on_event resolution are also unwired. Everything right of <em>ready</em> is real SQL with no application caller. Source: docs/scheduler.md, "What this does not do (yet)".')}</div></div>`;
};

V.realtime = () => {
  const open = last(D.tables, 1)[0] + (state.faults.errors ? 0 : 0);
  const rr = O.rng(31); const tbl = Array.from({ length: D.P ? 8 : 2 }, (_, i) => ({ id: 'tbl_' + O.hex(rr, 6), seats: i % 5 === 4 ? '1/2' : '2/2', age: Math.round(40 + rr() * 2400), frame: Math.round(rr() * 18), game: ['connect4', 'war', 'pictionary', 'uno'][i % 4] }));
  const reasons = [['peer_left', 71], ['peer_error', 9], ['peer_timeout', 14], ['expired', 6]];
  return head(`Realtime &middot; ${state.env}`, 'Game-table WebSockets', 'Ephemeral two-seat tables. The server holds them in memory and discards them the instant they close; the console sees shape and health, never moves or chat.') +
    `<div class="grid">
      ${tile({ label: 'Open tables', value: N(open), sub: 'game_tables_open', status: 'built', src: 'GET /internal/metrics', spark: D.tables }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Connections', value: N(Math.round(open * 1.9)), sub: 'sockets, open or half-open', status: 'proposed', src: 'no counter today' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Heartbeat', value: '20 / 10', unit: 's', sub: 'ping interval / pong timeout', status: 'built', src: 'server/game_tables.mjs GAME_PING_INTERVAL_MS, GAME_PONG_TIMEOUT_MS' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'peer_timeout closes', value: D.P ? '14' : '0', unit: '%', sub: 'of closes in range', status: 'proposed', src: 'endTable(reason) has no counter' }).replace('class="card', 'class="s3 card')}
    </div>
    <div class="grid"><div class="s8">${panel({ title: 'Open tables over time', status: 'partial', src: 'game_tables_open is a gauge; history needs a scraper',
      why: 'Tables are in-process memory. A restart drops every live game, so open-table count tells you the cost of a deploy at this moment.',
      body: line('tables', { title: 'Open tables', x: D.x, series: [{ name: 'tables', v: D.tables, color: 'var(--c5)' }], area: true, fmt: (v) => N(v) }) })}</div>
      <div class="s4">${panel({ title: 'Close reasons', sub: 'share of table closes', status: 'proposed', src: 'endTable(reason) reasons: peer_left, peer_error, peer_timeout, expired',
        why: 'A rising peer_timeout share means flaky networks or a heartbeat that is too tight for kids on tablets.',
        body: reasons.map(([k, v]) => `<div style="margin-bottom:9px"><div class="row" style="justify-content:space-between"><span class="mono">${k}</span><span>${v}%</span></div><div class="progress"><i style="width:${v}%"></i></div></div>`).join('') })}</div></div>
    <div class="grid"><div class="s7">${panel({ title: 'Tables now', sub: 'ids hashed; no seat names, no moves', status: 'proposed', src: 'gameTables Map in server/game_tables.mjs is not exposed',
      body: table('tbls', [{ k: 'id', label: 'Table', mono: true, f: (r) => r.id }, { k: 'game', label: 'Game', f: (r) => r.game }, { k: 'seats', label: 'Seats', f: (r) => r.seats === '2/2' ? r.seats : st('warn', r.seats + ' waiting') }, { k: 'age', label: 'Age', num: true, f: (r) => fdur(r.age) }, { k: 'frame', label: 'Last frame', num: true, f: (r) => r.frame + 's ago' }], tbl, { caption: 'Open tables', emptyTitle: 'No open tables', emptyBody: 'No game is in progress.' }) })}</div>
      <div class="s5">${panel({ title: 'Per-principal frame rate', sub: 'top principals, frames/s (hashed)', status: 'proposed', src: 'no per-principal counters; maxPayload = MAX_MESSAGE_BYTES x 4 is enforced',
        why: 'The server caps frame size but not frame rate. A noisy client shows up here before it shows up as latency.',
        body: bars([9, 6, 5, 4, 3, 3, 2, 2, 1, 1], { names: ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9', 'p10'], h: 110, label: 'Frames per second per principal' }) })}</div></div>`;
};

V.database = () => {
  const tab = curTab('db', 'migrations'); const P = D.P;
  const mig = O.MIGRATIONS.map((m, i) => ({ f: m + '.sql', n: m.slice(0, 4), applied: !(P && i >= O.MIGRATIONS.length - 2), sha: O.hex(O.rng(i + 7), 12), ms: Math.round(12 + O.rng(i + 3)() * 380) }));
  const body = {
    migrations: () => panel({ title: 'Migrations: applied vs repo', sub: `${mig.filter((m) => m.applied).length} applied of ${mig.length} in repo &middot; 0019 intentionally absent`, status: 'built', src: 'tools/migrate.mjs; table schema_migration(filename, checksum, duration_ms)',
      why: 'migrate.mjs refuses a changed file (checksum mismatch) so a migration edited after apply cannot silently diverge. The console surfaces that state; it does not run migrations.',
      body: (P ? notice('warn', '<strong>2 repo-only:</strong> 0037_fk_indexes and 0038_paired_device_credential are not applied to prod (sample rollout state).') : '') + table('mig', [{ k: 'f', label: 'File', mono: true }, { k: 'applied', label: 'State', v: (m) => +m.applied, f: (m) => m.applied ? st('ok', 'applied') : st('warn', 'repo only') }, { k: 'sha', label: 'sha256 (12)', mono: true, nosort: true, f: (m) => m.applied ? m.sha : '<span style="color:var(--ink-3)">-</span>' }, { k: 'chk', label: 'Checksum', nosort: true, f: (m) => m.applied ? st('ok', 'match') : '-' }, { k: 'ms', label: 'Took', num: true, f: (m) => m.applied ? fms(m.ms) : '-' }], mig, { caption: 'Migrations' }) }),
    pool: () => `<div class="grid"><div class="s6">${panel({ title: 'Connection pool', sub: 'DB_POOL_MAX = 10 &middot; statement_timeout 30 s', status: 'built', src: 'metrics.snapshot().pool {total, idle, waiting}; packages/db/src/pool.ts',
      why: 'The pool is small on purpose. Waiting > 0 for more than a minute means requests are queuing for a connection; /healthz is bounded to 3 s precisely so it reports that.',
      body: `<dl class="kv" style="margin-bottom:10px"><dt>total</dt><dd>${last(D.pool)[0] + 2}</dd><dt>idle</dt><dd>2</dd><dt>waiting</dt><dd>0</dd></dl>` + line('pool', { title: 'Pool in use', x: D.x, series: [{ name: 'in use', v: D.pool, color: 'var(--c2)' }], max: 10, thr: [{ v: 10, label: 'DB_POOL_MAX 10' }], h: 120, fmt: (v) => N(v) }) })}</div>
      <div class="s6">${panel({ title: 'Slow queries', sub: 'normalised fingerprints; parameters are never stored', status: 'proposed', src: 'needs pg_stat_statements; not enabled by any migration',
        why: 'Fingerprints contain placeholders only, so no child or family value can appear. Without this, a slow route has no explanation beyond ms.',
        body: table('slow', [{ k: 'q', label: 'Fingerprint', mono: true, f: (r) => esc(r.q) }, { k: 'calls', label: 'Calls', num: true, f: (r) => N(r.calls) }, { k: 'mean', label: 'Mean', num: true, f: (r) => fms(r.mean) }, { k: 'max', label: 'Max', num: true, f: (r) => fms(r.max) }], [{ q: 'SELECT ... FROM delivery_intent WHERE state = $1 AND ...', calls: 9120, mean: 3.4, max: 88 }, { q: 'SELECT ... FROM message_log WHERE child_id = $1 ORDER BY seq', calls: 4410, mean: 5.1, max: 241 }, { q: 'SELECT ... FROM health_check', calls: 288, mean: 41, max: 190 }, { q: 'UPDATE device_pairing_code SET failed_attempts = ...', calls: 311, mean: 1.8, max: 12 }], { sort: { k: 'mean', dir: 'desc' }, caption: 'Slow queries' }) })}</div></div>`,
    tables: () => { const rr = O.rng(88); const rows = O.TRACKED.concat(O.UNTRACKED).map((t, i) => ({ t, rows: Math.round(Math.pow(10, 1 + rr() * (t === 'message_log' || t === 'delivery_intent' ? 4.3 : 3.2))), mb: +(rr() * (t === 'media_artifact' || t === 'message_log' ? 90 : 18)).toFixed(1), rls: O.TRACKED.includes(t), force: O.TRACKED.includes(t) })); return panel({ title: 'Table sizes and RLS / FORCE', sub: 'row counts and bytes only', status: 'partial', src: 'rls_unforced checks relrowsecurity + relforcerowsecurity for 25 hand-listed tables (0029); sizes proposed',
      why: 'RLS is the main isolation mechanism between families. FORCE matters because the table owner would otherwise bypass it. The check is a fixed list, so a new table needs adding by hand (see Health).',
      body: table('tsz', [{ k: 't', label: 'Table', mono: true }, { k: 'rows', label: 'Rows', num: true, f: (r) => N(r.rows) }, { k: 'mb', label: 'Size', num: true, f: (r) => N(r.mb, 1) + ' MB' }, { k: 'rls', label: 'RLS', v: (r) => +r.rls, f: (r) => r.rls ? st('ok', 'enabled') : st('muted', 'not tracked') }, { k: 'force', label: 'FORCE', v: (r) => +r.force, f: (r) => r.force ? st('ok', 'forced') : st('muted', 'not tracked') }], rows, { sort: { k: 'mb', dir: 'desc' }, caption: 'Tables' }) }); },
    indexes: () => `<div class="grid"><div class="s6">${panel({ title: 'Index health', status: 'proposed', src: '0037_fk_indexes.sql added FK indexes; no monitoring of use or bloat', why: 'Foreign keys without indexes were found and fixed once. Monitoring keeps it fixed.',
      body: `<dl class="kv"><dt>FK columns without index</dt><dd>${st('ok', '0')}</dd><dt>Unused indexes (30 d)</dt><dd>3</dd><dt>Bloat &gt; 40%</dt><dd>0</dd><dt>Invalid indexes</dt><dd>0</dd></dl>` })}</div>
      <div class="s6">${panel({ title: 'Replication and backup lag', status: 'proposed', src: 'single Postgres primary in both compose files; no replica, no WAL archiving', why: 'Honest empty state: there is no replica to lag. The only recovery point is the nightly dump (see Backups).',
        body: empty('No replica configured', 'docker-compose.prod.yml runs one Postgres. Recovery point objective is therefore up to 24 h.', '') })}</div></div>`,
  }[tab]();
  return head(`Database &middot; ${state.env}`, 'Database', 'Schema state, pool pressure and isolation. The operator role never needs SELECT on family data; this page reads catalogs and counters only.') +
    tabs('db', [['migrations', 'Migrations'], ['pool', 'Pool & queries'], ['tables', 'Tables & RLS'], ['indexes', 'Indexes & lag']]) + (tab === 'pool' || tab === 'indexes' ? body : `<div class="grid"><div class="s12">${body}</div></div>`);
};

V.backups = () => {
  const P = D.P; const r = state.restore;
  const files = D.files;
  const ret = files.map((f) => `<div class="uptime-cell" style="flex:1"></div>`).join('');
  const days = Array.from({ length: 35 }, (_, i) => { const age = 34 - i; const kept = age < 7 || [7, 14, 21, 28].includes(age); return `<i class="${kept ? '' : 'c'}" style="${kept ? '' : 'background:var(--line-strong)'}" title="${age} d ago: ${kept ? (age < 7 ? 'daily kept' : 'weekly kept') : 'pruned'}"></i>`; }).join('');
  const steps = ['Choose backup', 'Choose target', 'Dry run', 'Confirm'];
  const wiz = () => {
    const s = r.step; const f = files[r.pick];
    const stepBody = [
      `<div class="field"><span class="lab">Backup</span>${files.slice(0, 5).map((x, i) => `<label style="display:block"><input type="radio" name="pick" data-act="rpick" data-i="${i}" ${r.pick === i ? 'checked' : ''}>${esc(x.name)} <span style="color:var(--ink-3)">${N(x.db, 0)} MB db + ${N(x.media, 1)} GB media</span></label>`).join('')}</div>`,
      `<div class="field"><span class="lab">Target</span><label style="display:block"><input type="radio" name="tg" data-act="rtarget" data-v="scratch" ${r.target === 'scratch' ? 'checked' : ''}>New scratch database (olive_restore_check). Safe: this is what backup-restore-verify.sh does.</label><label style="display:block"><input type="radio" name="tg" data-act="rtarget" data-v="prod" ${r.target === 'prod' ? 'checked' : ''}>Replace production (in place)</label>${r.target === 'prod' ? notice('crit', '<strong>Disaster path.</strong> Requires an incident, a second approver and a typed phrase. Never automatic: docs/backup-and-restore.md says restore is by hand.') : ''}</div>`,
      r.dry ? `<ul class="steps">${r.dry.map((x) => `<li class="${x.ok ? 'done' : 'cur'}"><span>${esc(x.t)}<br><span class="mono" style="color:var(--ink-3)">${esc(x.d)}</span></span></li>`).join('')}</ul>` : `<p>The dry run reads the backup and checks it; it writes nothing and connects to nothing but the scratch target.</p><button class="btn primary" data-act="rdry">Run dry run</button>`,
      `<div class="field"><label for="rph">Type <code>restore ${r.target === 'prod' ? 'prod' : 'scratch'}</code> to confirm</label><input id="rph" type="text" autocomplete="off" data-fid="rph"></div><div class="field"><label for="rrs">Reason (audited)</label><textarea id="rrs" data-fid="rrs"></textarea></div>${r.target === 'prod' ? '<div class="notice warn">Second approver: o.baker (responder) must approve in the console. <em>Proposed control.</em></div>' : ''}<button class="btn ${r.target === 'prod' ? 'danger' : 'primary'}" data-act="rgo">Start restore</button>`][s];
    return `<ol class="row" style="list-style:none;padding:0;margin:0 0 12px">${steps.map((t, i) => `<li class="chip ${i === s ? 'info' : i < s ? 'ok' : ''}">${i + 1}. ${t}</li>`).join('')}</ol>${stepBody}
      <div class="row" style="margin-top:12px">${s > 0 ? '<button class="btn" data-act="rstep" data-d="-1">Back</button>' : ''}${s < 3 && (s !== 2 || r.dry) ? '<button class="btn" data-act="rstep" data-d="1">Next</button>' : ''}</div>`;
  };
  return head(`Backups &middot; ${state.env}`, 'Backups and restore', 'Nightly dump, 7 daily + 4 weekly, optional encryption and off-host copy. A backup nobody has restored is a hope.') +
    (P ? '' : `<div class="grid"><div class="s12">${notice('info', '<strong>Backups are off in dev:</strong> the job logs <code>status=skipped reason=not_configured</code> unless BACKUP_DIR and BACKUP_DATABASE_URL are set. Showing the prod shape below as a reference with dev values empty.')}</div></div>`) +
    `<div class="grid">
      ${tile({ label: 'Newest dump', value: P ? '7h' : '-', unit: P ? ' old' : '', sub: 'stale alarm at 36 h (BACKUP_MAX_AGE_HOURS)', status: 'built', src: 'tools/backup_lib.mjs staleBackupAlarm()' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Encryption', value: P ? 'AES-256-GCM' : 'off', sub: P ? 'passphrase not on the same disk (sample)' : 'default is off', status: 'built', src: 'BACKUP_ENCRYPTION_PASSPHRASE; tools/backup-decrypt.mjs' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Last verified drill', value: P ? '19' : '-', unit: P ? ' days ago' : '', sub: 'not scheduled; run by hand', status: 'built', src: 'tools/backup-restore-verify.sh', warn: P }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Off-host copy', value: P ? 'synced' : 'off', sub: P ? 'BACKUP_SYNC_COMMAND exit 0, 03:07Z' : 'no destination is invented', status: 'built', src: 'BACKUP_SYNC_COMMAND (shell command; none shipped)' }).replace('class="card', 'class="s3 card')}
    </div>
    <div class="grid"><div class="s7">${panel({ title: 'Schedule and retention', sub: 'runs at SCHEDULER_HOUR_UTC (03:00); keeps the newest per day for 7 days, per ISO week for 4, always the newest', status: 'built', src: 'tools/scheduler.mjs backup; BACKUP_DAILY_KEEP / BACKUP_WEEKLY_KEEP',
      why: 'Retention counts days that have a backup, so a ten-day outage does not wipe history on the first night back. A failing night prunes nothing.',
      body: `<div class="uptime" role="img" aria-label="35 days: 7 daily and 4 weekly kept, others pruned">${days}</div><div class="legend"><span><i class="sw" style="border-color:var(--ok)"></i>kept</span><span><i class="sw" style="border-color:var(--line-strong)"></i>pruned</span></div>
      <div class="tw" style="margin-top:10px">${P ? table('files', [{ k: 'name', label: 'File', mono: true }, { k: 'kind', label: 'Class', f: (f) => `<span class="chip">${f.kind}</span>` }, { k: 'db', label: 'DB', num: true, f: (f) => N(f.db) + ' MB' }, { k: 'media', label: 'Media', num: true, f: (f) => N(f.media, 1) + ' GB' }, { k: 'synced', label: 'Off-host', f: (f) => st('ok', 'synced') }], files, { caption: 'Backups' }) : empty('No backups in dev', 'BACKUP_DIR is unset, so none were promised.', 'BACKUP_DIR=./backups BACKUP_DATABASE_URL=postgres://backup_reader:...@host/olive_dev node tools/scheduler.mjs run backup')}</div>` })}</div>
      <div class="s5">${panel({ title: 'Restore wizard', sub: 'a front end over the existing scripts', status: 'proposed', src: 'built underneath: tools/restore-db.sh, restore-media.sh, backup-decrypt.mjs, backup-restore-verify.sh. The wizard and dry run are not built.',
        why: 'Restore is the moment of highest stress and highest risk. Default to a scratch target, make production restore require an incident, a second person and a typed phrase, and audit every step.',
        body: P ? wiz() : empty('Nothing to restore', 'No backups in dev.') })}</div></div>`;
};

V.storage = () => {
  const P = D.P; const used = P ? 41.2 : .6; const cap = P ? 200 : 20; const pct = used / cap * 100;
  const days = (cap - used) / ((D.mediaGB[89] - D.mediaGB[59]) / 30);
  const rr = O.rng(66); const bins = [32, 51, 44, 26, 14, 7, 3, 0]; const bn = ['<10%', '10-20', '20-30', '30-40', '40-50', '50-60', '60-80', '80+'];
  return head(`Storage &middot; ${state.env}`, 'Media volume and retention', 'Bytes and counts, never the media. Per-child usage is shown only as an anonymous distribution; bins under 5 children are suppressed.') +
    `<div class="grid">
      <div class="s4">${panel({ title: 'Media volume', sub: `${fgb(used)} of ${fgb(cap)}`, status: 'proposed', src: 'MEDIA_STORAGE_ROOT filesystem; statfs not exposed',
        why: 'The signed-media route serves from one filesystem volume. Running out of it fails uploads and the nightly media archive together.',
        body: `<div class="meter" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${N(pct, 0)}" aria-label="Volume used"><i class="${pct > 85 ? 'crit' : pct > 70 ? 'warn' : ''}" style="width:${pct}%"></i></div><dl class="kv"><dt>used</dt><dd>${N(pct, 1)}%</dd><dt>growth</dt><dd>${N((D.mediaGB[89] - D.mediaGB[59]) / 30 * 1024, 0)} MB/day</dd><dt>full in (linear)</dt><dd>${N(days / 30, 0)} months</dd><dt>preserved</dt><dd>38%</dd><dt>expiring (COPPA clock)</dt><dd>62%</dd></dl>` })}</div>
      <div class="s8">${panel({ title: 'Per-child usage vs quota', sub: 'distribution of children by % of quota; aggregate only', status: 'proposed', src: 'no quota concept exists in the repo (searched packages/ and server/)',
        why: 'A quota is an owner decision (value and what happens at 100%). Until then this shows the distribution so the decision can be made with real numbers. Names and ids are not part of the view.',
        body: bars(bins, { names: bn, h: 120, label: 'Children by quota percent' }) + `<p style="margin-top:8px;font-size:12px;color:var(--ink-3)">The 80+ bin is empty and would be suppressed anyway (n &lt; 5).</p>` })}</div></div>
    <div class="grid"><div class="s7">${panel({ title: 'Orphan sweep results', sub: 'reap-media, last 14 runs', status: 'built', src: 'tools/scheduler.mjs reap-media; packages/storage/src/storage.ts reap()',
      why: 'The reaper deletes the blob first, then the row, and tombstones on failure so a stuck row never vanishes. blobs_already_gone sustained above zero usually means the scheduler is not mounted on the real volume (this has happened once).',
      body: table('reap', [{ k: 'd', label: 'Run', mono: true }, { k: 'ex', label: 'examined', num: true }, { k: 'bd', label: 'blobs_deleted', num: true }, { k: 'ag', label: 'already_gone', num: true, f: (r) => r.ag ? st('warn', r.ag) : 0 }, { k: 'rd', label: 'rows_deleted', num: true }, { k: 'tb', label: 'tombstoned', num: true, f: (r) => r.tb ? st('crit', r.tb) : 0 }, { k: 'sp', label: 'skipped_preserved', num: true }], Array.from({ length: 6 }, (_, i) => ({ d: dstr(Date.now() - i * 86400000), ex: 4 + i % 4, bd: 2 + i % 3, ag: 0, rd: 2 + i % 3, tb: i === 4 ? 1 : 0, sp: i % 3 })), { caption: 'Reap results', emptyTitle: 'No runs' }) })}</div>
      <div class="s5">${panel({ title: 'Unresolved tombstones and blob orphans', status: 'partial', src: 'retention_breach view (built); blob-without-row walk (proposed)', why: 'A tombstone older than a day is a live COPPA retention exposure and is already a critical health check.',
        body: `<dl class="kv"><dt>reap_tombstone &gt; 1 day (retention_breach)</dt><dd>${st('ok', '0')}</dd><dt>Blobs with no row</dt><dd>${st('muted', 'not measured')}</dd><dt>Rows with no blob</dt><dd>${st('muted', 'not measured')}</dd></dl>` })}</div></div>`;
};

V.security = () => {
  const flt = state.faults.pairing; const miss = last(D.pairMiss)[0];
  const th = 15; const firing = miss > th;
  return head(`Security centre &middot; ${state.env}`, 'Security centre', 'Counts and rates only. No credential, token, code, IP address or user agent is ever displayed.') +
    (firing ? `<div class="grid"><div class="s12">${notice('crit', `<strong>Brute-force alert:</strong> pairing-code miss rate ${N(miss, 1)}% over 15 min (threshold ${th}%, min 30 attempts). Open codes are protected by a per-code lockout (failed_attempts) and the per-IP / per-identifier limiter; consider tightening AUTH_RATE_IP_PER_MIN.`)}</div></div>` : '') +
    `<div class="grid">
      ${tile({ label: 'Sessions', value: N(D.fam.sessions), sub: 'active, count only', status: 'proposed', src: 'session store; count only' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Paired devices', value: N(D.fam.paired), sub: '0038 adds device credentials', status: 'partial', src: 'device_pairing_code, 0032 + 0038' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Passkeys registered', value: N(D.fam.passkeys), sub: 'webauthn_credential rows', status: 'partial', src: '0008_auth_credentials.sql (count not exposed)' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Rate-limited events', value: N(D.rl.reduce((a, b) => a + b, 0)), sub: 'rate_limited_total', status: 'built', src: 'server/index.mjs metrics.inc(\'rate_limited_total\')' }).replace('class="card', 'class="s3 card')}
    </div>
    <div class="grid"><div class="s6">${panel({ title: 'Pairing-code miss rate', sub: 'failed redeem attempts / attempts', status: 'partial', src: 'device_pairing_code.failed_attempts is built (lockout); the aggregate rate and alert are proposed',
      actions: `<button class="btn sm" data-act="fault" data-k="pairing">${flt ? 'Clear sample burst' : 'Simulate burst'}</button>`,
      why: 'A 6-digit numeric fallback is brute-forceable without a lockout, so the per-code lockout exists. A rising aggregate miss rate across many codes is the signal the lockout cannot show.',
      body: line('pm', { title: 'Pairing miss rate', x: D.x, series: [{ name: 'miss %', v: D.pairMiss, color: 'var(--c4)' }], fmt: (v) => N(v, 1), unit: '%', thr: [{ v: th, label: `alert ${th}%` }], h: 130 }) })}</div>
      <div class="s6">${panel({ title: 'Auth failures and rate-limit events', status: 'partial', src: 'createAuthLimiter(): 30/min per IP, 10/min per identifier (server/rate_limit.mjs); split by reason is proposed',
        why: 'The unauthenticated /v1/auth/ surface is throttled before any work. These two counters separate a single noisy source from a distributed attempt.',
        body: line('af', { title: 'Auth failures and rate limits', x: D.x, series: [{ name: 'auth failures', v: D.authFail, color: 'var(--c3)' }, { name: 'rate-limited', v: D.rl, color: 'var(--c2)', dash: true }], h: 130, fmt: (v) => N(v) }) })}</div></div>
    <div class="grid"><div class="s6">${panel({ title: 'Secret and config validation', sub: 'set / unset / strength only; values are never read into the console', status: 'partial', src: 'server/signed_media.mjs + test/media_signing_secret.test.mjs; other checks proposed',
      body: table('cfg', [{ k: 'k', label: 'Setting', mono: true }, { k: 'v', label: 'State', nosort: true, f: (r) => st(r.kind, r.v) }, { k: 'n', label: 'Note', nosort: true, f: (r) => `<span style="color:var(--ink-2)">${esc(r.n)}</span>` }], [{ k: 'MEDIA_SIGNING_SECRET', v: 'set, 32+ bytes', kind: 'ok', n: 'boot refuses a weak one' }, { k: 'INTERNAL_METRICS_TOKEN', v: 'set', kind: 'ok', n: 'else loopback only' }, { k: 'TRUST_PROXY', v: D.P ? '1' : 'unset', kind: D.P ? 'ok' : 'info', n: 'XFF honoured only behind your proxy' }, { k: 'BACKUP_ENCRYPTION_PASSPHRASE', v: D.P ? 'set' : 'unset', kind: D.P ? 'ok' : 'warn', n: 'not recoverable if lost' }, { k: 'APP_OWNER_PASSWORD', v: D.P ? 'non-default' : 'default (dev)', kind: D.P ? 'ok' : 'info', n: 'dev compose hardcodes app_owner' }], { caption: 'Config validation' }) })}</div>
      <div class="s6">${panel({ title: 'Privileged role usage', sub: 'which DB roles connected, count of sessions', status: 'proposed', src: 'roles exist: app_owner, backup_reader (0022), app role; no usage log',
        why: 'backup_reader exists so the dump identity is not the owner. Seeing it connect at any hour but 03:00 would be the alert.',
        body: table('roles', [{ k: 'r', label: 'Role', mono: true }, { k: 'u', label: 'Used by' }, { k: 'n', label: 'Conns, 24 h', num: true }, { k: 'w', label: 'Expected', nosort: true, f: (r) => st(r.ok ? 'ok' : 'warn', r.ok ? 'yes' : 'unexpected') }], [{ r: 'app (NOBYPASSRLS)', u: 'server', n: 1840, ok: true }, { r: 'app_owner', u: 'scheduler, migrate', n: 12, ok: true }, { r: 'backup_reader', u: 'scheduler backup', n: 1, ok: true }], { caption: 'Roles' }) })}</div></div>
    <div class="grid"><div class="s12">${panel({ title: 'Supply chain and advisories', status: 'partial', src: '.github/workflows/verify.yml, publish-image.yml, scaffold/package-lock.json exist; advisory feed is proposed',
      why: 'The image is published from CI. Knowing which advisories apply to the running image closes the loop between a CVE feed and what is deployed.',
      body: `<div class="split"><dl class="kv"><dt>Lockfile committed</dt><dd>${st('ok', 'yes')}</dd><dt>CI verify workflow</dt><dd>${st('ok', 'present')}</dd><dt>Image publish workflow</dt><dd>${st('ok', 'present')}</dd></dl><dl class="kv"><dt>Critical advisories</dt><dd>0</dd><dt>High</dt><dd>${st('warn', '1')}</dd><dt>Last scan</dt><dd>sample: 6 h ago</dd></dl></div>` })}</div></div>`;
};

V.audit = () => {
  const fam = D.fam.list; const pass = fam.filter((f) => f.chain === 'pass').length;
  const ver = state.verifyRun;
  return head(`Audit log &middot; ${state.env}`, 'Audit log', 'Two different logs: the families\' own hash-chained handover log (we verify integrity, never read it) and the operators\' action log (we read and export it).',
      `<button class="btn" data-act="verify">${ver ? 'Re-run verification' : 'Verify all chains'}</button>`) +
    `<div class="grid"><div class="s5">${panel({ title: 'Hash-chain integrity', sub: 'message_log per family: pass / fail only', status: 'partial', src: 'message_log(prev_hash, hash, seq) in 0006; verifyChain() in packages/ledger; the per-family sweep and result store are proposed',
      why: 'The handover log is the part of Olive a court might rely on. A broken chain is the most serious integrity event the system can have (prohibition P8). The console never reads entries: it only receives pass/fail and counts.',
      body: `<div class="row" style="justify-content:space-between"><div><div class="tile"><div class="val" style="font-size:30px">${pass}<small> of ${D.fam.total === 186 ? 186 : fam.length} pass</small></div></div></div>${ver ? st('ok', 'verified just now') : st('muted', 'last full run: sample 3 h ago')}</div>
        <p style="color:var(--ink-3);font-size:12px">Showing a sample of ${fam.length} families. One is <em>pending</em> (never verified): a new family with no entries yet is not a failure.</p>${table('chains', [{ k: 'id', label: 'Family', mono: true }, { k: 'entries', label: 'Entries', num: true, f: (f) => N(f.entries) }, { k: 'chain', label: 'Chain', f: (f) => f.chain === 'pass' ? st('ok', 'pass') : st('muted', 'unverified') }], fam.slice(0, 8), { sort: { k: 'entries', dir: 'desc' }, caption: 'Chains' })}` })}</div>
      <div class="s7">${panel({ title: 'Operator action log', sub: 'every console action; itself hash-chained', status: 'proposed', src: 'no operator audit table exists; this session\'s actions append here live',
        why: 'Operators hold power over a child\'s family data, even indirectly. Every write, export, support-case entry and config view is recorded with a reason, and the log chains hashes so tampering is visible.',
        body: table('opl', [{ k: 'n', label: '#', mono: true, f: (e) => 'A-' + String(e.n).padStart(4, '0') }, { k: 't', label: 'When', mono: true, f: (e) => tstr(e.t).slice(5, 16) }, { k: 'actor', label: 'Actor', f: (e) => `${esc(e.actor)} <span style="color:var(--ink-3)">${e.role}</span>` }, { k: 'action', label: 'Action', mono: true }, { k: 'target', label: 'Target', mono: true, f: (e) => esc(e.target) }, { k: 'reason', label: 'Reason', nosort: true, f: (e) => esc(e.reason) }, { k: 'hash', label: 'Chain', mono: true, nosort: true, f: (e) => `${e.prev.slice(0, 4)}→${e.hash.slice(0, 4)}` }], state.audit, { sort: { k: 'n', dir: 'desc' }, caption: 'Operator actions' }) })}</div></div>
    <div class="grid"><div class="s12">${panel({ title: 'Export history', sub: 'family exports (guardian-initiated) and operator exports of this console', status: 'partial', src: 'export_record table + /v1/children/:childId/export are built; operator export of console data is proposed',
      why: 'A family export is a court-grade document. Operators see that one happened and its size, never what it contained.',
      body: table('exp', [{ k: 'when', label: 'When', mono: true }, { k: 'who', label: 'Initiated by' }, { k: 'what', label: 'Kind' }, { k: 'size', label: 'Size', num: true }, { k: 'st', label: 'Attested', nosort: true, f: (r) => st('ok', 'hash verified') }], [{ when: dstr(Date.now() - 2 * 86400000), who: 'guardian of fam_' + O.hex(O.rng(2), 6), what: 'court export', size: '1.4 MB' }, { when: dstr(Date.now() - 9 * 86400000), who: 'guardian of fam_' + O.hex(O.rng(3), 6), what: 'raw export', size: '8.2 MB' }, { when: dstr(Date.now() - 14 * 86400000), who: 'operator m.okafor', what: 'console audit CSV', size: '41 KB' }], { caption: 'Exports' }) })}</div></div>`;
};

V.tenants = () => {
  const fam = D.fam.list; const flt = state.familyFilter;
  const dh = D.P ? Array.from({ length: 5 }, (_, i) => { const dep = Date.now() - (60 + i * 39) * 86400000; return { id: 'acct_' + O.hex(O.rng(i + 400), 6), dep, min: dep + 182 * 86400000, max: dep + 365 * 86400000, state: i === 0 ? 'owner hold' : 'in window' }; }) : [];
  const sc = state.supportCase; const end = Date.now() + 47 * 60000;
  const cases = [
    { id: 'c_91a2', fam: 'fam_' + fam[0].id.slice(4), st: sc === 1 ? 'active' : 'awaiting consent', scope: 'health flags + counters only' },
    { id: 'c_77be', fam: 'fam_' + fam[fam.length - 1].id.slice(4), st: 'expired', scope: 'health flags + counters only' },
  ];
  return head(`Tenants &middot; ${state.env}`, 'Tenants and support', 'A tenant is a family. The console identifies one by a truncated hash and shows counts and health flags; names of children and guardians never appear.') +
    `<div class="grid">
      ${tile({ label: 'Families', value: N(D.fam.total), sub: `${D.fam.a7} active in 7 d`, status: 'proposed', src: 'COUNT(*) over the family graph' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Children', value: N(D.fam.kids), sub: 'count only; no names', status: 'proposed' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'Families with a flag', value: fam.filter((f) => f.flags.length).length + '', sub: `of ${fam.length} sampled`, status: 'proposed' }).replace('class="card', 'class="s3 card')}
      ${tile({ label: 'In deletion hold', value: String(dh.length), sub: '6-12 month recovery window', status: 'partial', src: 'app_user.deactivated_at (0011)' }).replace('class="card', 'class="s3 card')}
    </div>
    <div class="grid"><div class="s8">${panel({ title: 'Family health flags', sub: 'sample of ' + fam.length + ' families; flags derive from the Health checks', status: 'proposed', src: 'per-family rollup of health_check; today the view returns global counts only',
      actions: `<label class="sel"><span class="sr">Filter flag</span><select id="famFilter" data-act="famfilter"><option value="all">All</option><option value="flagged" ${flt === 'flagged' ? 'selected' : ''}>Flagged only</option></select></label>`,
      why: 'Support needs to know "is this family affected" without opening anything. A flag says which check fails for them and nothing about their content.',
      body: table('fams', [{ k: 'id', label: 'Family', mono: true }, { k: 'created', label: 'Since', mono: true, f: (f) => dstr(f.created) }, { k: 'kids', label: 'Children', num: true }, { k: 'guardians', label: 'Guardians', num: true }, { k: 'devices', label: 'Devices', num: true }, { k: 'last', label: 'Last active', num: true, f: (f) => f.last < 1 ? 'today' : N(f.last) + ' d' }, { k: 'flags', label: 'Flags', nosort: true, f: (f) => f.flags.length ? f.flags.map((x) => `<span class="chip ${x === 'stalled_delivery' ? 'crit' : 'warn'}">${x}</span>`).join(' ') : '<span style="color:var(--ink-3)">none</span>' }], fam, { filter: (f) => flt === 'all' || f.flags.length, caption: 'Families', emptyTitle: 'No flagged families', emptyBody: 'Every sampled family passes every check.' }) })}</div>
      <div class="s4">${panel({ title: 'Support case', sub: 'consent-gated and time-boxed', status: 'proposed', src: 'no support-case model exists',
        why: 'Operators never open a family on their own. A guardian grants access in the app for a fixed window and a defined scope; the grant expires by itself and every read is audited. Scope here is health flags and counters, never content.',
        body: cases.map((c) => `<div class="check ${c.st === 'active' ? 'ok' : c.st === 'expired' ? '' : 'warn'}" style="margin-bottom:10px"><div class="row" style="justify-content:space-between"><span class="nm">${c.id}</span><span class="chip ${c.st === 'active' ? 'ok' : c.st === 'expired' ? '' : 'warn'}">${c.st}</span></div><p class="mono">${c.fam}</p><p>Scope: ${c.scope}</p>${c.st === 'active' ? `<p>Time left <strong class="mono" data-countdown="${end}">47:00</strong> of 60 min</p><button class="btn sm" data-act="revokecase">End access now</button>` : c.st === 'awaiting consent' ? `<p>Waiting for the family\'s guardian to approve in the app.</p><button class="btn sm" data-act="grantcase">Simulate guardian consent</button>` : '<p>Window closed; access revoked automatically.</p>'}</div>`).join('') })}</div></div>
    <div class="grid"><div class="s12">${panel({ title: 'Deletion-hold queue', sub: 'deactivated accounts inside the 6-12 month recovery window', status: 'partial', src: 'built: app_user.deactivated_at (0011), deactivateAccount(). Not built: the recovery window, the restore action and the purge job (owner decision recorded: 6-12 months; exact value open).',
      why: 'Deletion removes login and undelivered items at once but keeps delivered messages, the handover log and the preserved archive. The hold lets a guardian change their mind. The purge schedule is shown here so nothing is erased early or forgotten.',
      body: dh.length ? table('hold', [{ k: 'id', label: 'Account', mono: true }, { k: 'dep', label: 'Deactivated', mono: true, f: (r) => dstr(r.dep) }, { k: 'win', label: 'Window (min → max)', nosort: true, f: (r) => { const t = (Date.now() - r.dep) / (r.max - r.dep) * 100; return `<div class="win" role="img" aria-label="${N(t, 0)}% through the maximum window"><i class="b" style="left:0;width:50%"></i><i class="e" style="left:50%;width:50%"></i><i class="m" style="left:${t}%"></i></div>`; } }, { k: 'min', label: 'Earliest purge', mono: true, f: (r) => dstr(r.min) }, { k: 'max', label: 'Latest purge', mono: true, f: (r) => dstr(r.max) }, { k: 'state', label: 'State', f: (r) => `<span class="chip ${r.state === 'owner hold' ? 'warn' : ''}">${r.state}</span>` }, { k: 'act', label: '', nosort: true, f: (r) => `<button class="btn sm" disabled title="Purge needs the window to elapse and a second approver">Purge</button>` }], dh, { sort: { k: 'dep', dir: 'asc' }, caption: 'Deletion holds' }) + notice('info', 'Purge buttons stay disabled until the earliest purge date has passed, and then need a second approver. Restore-on-request is handled by the family in the app, not by operators.') : empty('No deletion holds', 'No account is inside a recovery window in this environment.') })}</div></div>`;
};

V.flags = () => {
  if (!state.flags) state.flags = [
    { k: 'court_tier', d: 'Court-grade export tier for a family (per-child flag column).', on: true, built: 'built', src: 'db/migrations/0013_court_tier_flag.sql', scope: 'per child' },
    { k: 'adhoc_local_play', d: 'Offline local-network games; client side.', on: true, built: 'proposed', src: 'client only today', scope: 'device' },
    { k: 'colour_of_the_day', d: 'Colour-of-the-day child flow.', on: false, built: 'proposed', src: 'not a server flag', scope: 'family' },
    { k: 'delivery_worker', d: 'Start the planned delivery worker.', on: false, built: 'proposed', src: 'worker not built', scope: 'global' },
    { k: 'live_calls', d: 'Server-mediated calls. Direction is offline-first, so this stays parked.', on: false, built: 'proposed', src: '0018_call_log.sql exists; LiveKit parked', scope: 'global' },
  ];
  const cfg = [['DB_POOL_MAX', '10', 'built', 'packages/db/src/pool.ts'], ['DB_STATEMENT_TIMEOUT_MS', '30000', 'built', 'packages/db/src/pool.ts'], ['AUTH_RATE_IP_CAPACITY / _PER_MIN', '30 / 30', 'built', 'server/rate_limit.mjs'], ['AUTH_RATE_ID_CAPACITY / _PER_MIN', '10 / 10', 'built', 'server/rate_limit.mjs'], ['SCHEDULER_HOUR_UTC', '3', 'built', 'docs/scheduler.md'], ['BACKUP_DAILY_KEEP / WEEKLY_KEEP', '7 / 4', 'built', 'docs/backup-and-restore.md'], ['BACKUP_MAX_AGE_HOURS', '36', 'built', 'tools/backup_lib.mjs'], ['GAME_PING_INTERVAL_MS / PONG_TIMEOUT_MS', '20000 / 10000', 'built', 'server/game_tables.mjs (constants, not env)']];
  return head(`Flags & config &middot; ${state.env}`, 'Feature flags and configuration', 'Flags are the only runtime-changeable thing here. Config is environment-driven: the console shows it and links to a deploy, it does not edit a live process.') +
    `<div class="grid"><div class="s7">${panel({ title: 'Feature flags', sub: 'toggling asks for a reason and is audited', status: 'partial', src: 'only the court-tier flag exists server-side (0013); a general flag service is proposed',
      why: 'Flags let a risky path be switched off without a deploy. Most Olive behaviour is client-side or per-family today, so the honest list is short; each row says where its truth lives.',
      body: table('flags', [{ k: 'k', label: 'Flag', mono: true }, { k: 'd', label: 'What', nosort: true, f: (f) => `<span style="color:var(--ink-2)">${esc(f.d)}</span><br><span class="srcpath">${esc(f.src)}</span>` }, { k: 'scope', label: 'Scope' }, { k: 'built', label: 'Backing', f: (f) => src(f.built) }, { k: 'on', label: 'State', nosort: true, f: (f) => `<button class="btn sm" role="switch" aria-checked="${f.on}" data-act="flag" data-k="${f.k}" data-fid="flag-${f.k}">${f.on ? st('ok', 'on') : st('muted', 'off')}</button>` }], state.flags, { caption: 'Feature flags' }) })}</div>
      <div class="s5">${panel({ title: 'Effective configuration', sub: 'read-only; changing needs a deploy', status: 'partial', src: 'values read from the running process: proposed. Names and defaults are real.',
        body: table('cfgv', [{ k: 'k', label: 'Name', mono: true, nosort: true }, { k: 'v', label: 'Value', mono: true, nosort: true }], cfg.map(([k, v]) => ({ k, v })), { caption: 'Config' }) })}</div></div>`;
};

V.incidents = () => {
  const inc = state.incident;
  const past = [
    { id: 'INC-0003', sev: 'SEV3', t: Date.now() - 41 * 86400000, title: 'Rematerialize skipped one night after a lock held by a stale connection', area: 'delivery', mins: 38 },
    { id: 'INC-0002', sev: 'SEV2', t: Date.now() - 77 * 86400000, title: 'Reaper wrote tombstones: media volume not mounted in scheduler', area: 'storage', mins: 190 },
    { id: 'INC-0001', sev: 'SEV3', t: Date.now() - 120 * 86400000, title: 'Pool exhausted during a deploy', area: 'database', mins: 12 },
  ];
  const all = (inc ? [inc] : []).concat(state.incidents, past);
  const rb = O.RUNBOOKS;
  const sp = inc ? (inc.sev === 'SEV1' ? 'crit' : 'warn') : 'ok';
  const area = inc ? inc.areas : [];
  const spRow = (n, a) => `<div class="sp-r"><div class="t">${n}<span class="s ${area.includes(a) ? (inc.sev === 'SEV1' ? 'bad' : 'mid') : ''}">${area.includes(a) ? (inc.sev === 'SEV1' ? 'Major outage' : 'Degraded performance') : 'Operational'}</span></div><div class="uptime" aria-hidden="true">${Array.from({ length: 60 }, (_, i) => `<i class="${i === 20 && n === 'Delivery' ? 'w' : ''}"></i>`).join('')}</div><small>90 days (sample)</small></div>`;
  return head(`Incidents &middot; ${state.env}`, 'Incidents and runbooks', 'Declare early, communicate plainly. Incident text is linted: no emails, phone numbers, full ids or message content belong in it.',
      `<button class="btn ${inc ? '' : 'danger'}" data-act="${inc ? 'resolve' : 'declare'}">${inc ? 'Resolve incident' : 'Declare incident'}</button>`) +
    `<div class="grid"><div class="s6">${panel({ title: 'Timeline', sub: inc ? 'active incident first' : 'no active incident', status: 'proposed', src: 'no incident store; history here is sample',
      why: 'During an incident the timeline is the shared memory. Declaring writes the first entry, an audit record and opens the matching runbooks.',
      body: `<ol class="timeline">${(inc ? inc.events : []).map((e) => `<li class="${e.k}"><time>${tstr(e.t)}</time>${esc(e.text)}</li>`).join('')}${all.filter((x) => x !== inc && !x.events).map((p) => `<li class="ok"><time>${tstr(p.t)} &middot; ${p.sev} &middot; ${p.mins} min</time><strong>${p.id}</strong> ${esc(p.title)}<br><span class="chip">${p.area}</span></li>`).join('')}</ol>` })}</div>
      <div class="s6">${panel({ title: 'Status page preview', sub: 'what families would see: component names and a status, nothing else', status: 'proposed', src: 'no status page exists',
        why: 'Families are anxious by definition. The public page names components and plain status words only: no counts, no causes, no family data.',
        body: `<div class="statuspage"><div class="sp-h ${sp}">${inc ? (inc.sev === 'SEV1' ? 'We are experiencing a major outage' : 'Some parts of Olive are slower than usual') : 'All systems operational'}</div>${spRow('Sign-in', 'security')}${spRow('Delivery', 'delivery')}${spRow('Game tables', 'realtime')}${spRow('Photos and video', 'storage')}</div>` })}</div></div>
    <div class="grid"><div class="s12">${panel({ title: 'Runbooks', sub: 'each opens with the evidence panel; commands are the real ones', status: 'partial', src: 'steps cite tools that exist (scheduler.mjs, health-alert.mjs, backup scripts); the runbook store and checklists are proposed',
      body: `<div class="split">${rb.map((r) => `<details class="check ${r.status === 'proposed' ? 'prop' : ''}"><summary style="cursor:pointer;font-weight:600">${esc(r.title)} ${src(r.status)}</summary><ol class="steps" style="margin-top:10px">${r.steps.map((s) => `<li><span>${esc(s)}</span></li>`).join('')}</ol><pre style="margin-top:10px">${esc(r.cmd)}</pre></details>`).join('')}</div>` })}</div></div>`;
};

V.capacity = () => {
  const rep = state.replicas || 1; state.replicas = rep;
  const conns = 10 * rep + 10 + 2; const maxc = 100;
  const x = Array.from({ length: 120 }, (_, i) => Date.now() - (89 - i) * 86400000);
  const pad = (a, f) => ({ act: a.concat(Array(30).fill(null)), fc: Array(89).fill(null).concat([a[89]], f) });
  const fc = (a) => { const s = (a[89] - a[59]) / 30; return Array.from({ length: 30 }, (_, i) => a[89] + s * (i + 1)); };
  const rows = [
    ['Rate limits (TokenBuckets)', 'In-process Map per replica', 'Effective limits multiply by N; an attacker spreads requests across replicas', 'risk', 'Shared store (Redis / Postgres) or stick clients by IP'],
    ['Game tables (gameTables Map)', 'In-process; ws opened on one replica', 'Second seat landing on another replica cannot join; restart loses every live game', 'risk', 'Sticky routing by table id, or a pub/sub relay'],
    ['Metrics (Metrics class)', 'In-process counters', 'Each replica reports its own /internal/metrics; no aggregate', 'warn', 'Scrape every replica; sum in the collector'],
    ['Scheduler advisory locks', 'pg_try_advisory_lock, DB-level', 'Safe: only one runner holds a job lock at a time', 'ok', 'None needed'],
    ['Media storage (filesystem volume)', 'One local volume, signed URLs', 'Replicas must share the same volume or the signed route 404s', 'risk', 'Shared volume now; object storage later'],
    ['DB pool', 'DB_POOL_MAX 10 per process', `${rep} replica(s): ${conns} of ${maxc} Postgres connections (incl. scheduler and migrate)`, conns > 70 ? 'risk' : 'warn', 'PgBouncer or lower DB_POOL_MAX per replica'],
    ['/internal/metrics guard', 'Loopback only unless INTERNAL_METRICS_TOKEN', 'A scraper on another host needs the token', 'warn', 'Set the token before adding a collector'],
    ['Graceful shutdown (shutdown.mjs)', 'Per-process drain', 'Rolling deploys work, but open game tables are dropped at each step', 'warn', 'Drain tables first, or accept the cost'],
  ];
  return head(`Capacity & cost &middot; ${state.env}`, 'Capacity, headroom and cost', 'Forecasts use a straight line over the last 30 days. They are a planning aid, not a promise.') +
    `<div class="grid"><div class="s6">${panel({ title: 'Database size, 90 d + 30 d forecast', status: 'proposed', src: 'pg_database_size() history; not stored', why: 'Linear extrapolation is crude but enough to see months of headroom or weeks.',
      body: line('dbs', { title: 'Database size', x, series: [{ name: 'actual GB', v: pad(D.dbGB, fc(D.dbGB)).act, color: 'var(--c2)' }, { name: 'linear forecast', v: pad(D.dbGB, fc(D.dbGB)).fc, color: 'var(--c2)', dash: true }], fmt: (v) => N(v, 2), unit: ' GB', h: 130 }) + `<p style="margin-top:6px;color:var(--ink-2)">Forecast +30 d: <strong>${N(fc(D.dbGB)[29], 2)} GB</strong></p>` })}</div>
      <div class="s6">${panel({ title: 'Media volume, 90 d + 30 d forecast', status: 'proposed', src: 'MEDIA_STORAGE_ROOT statfs history', why: 'Media dominates storage and is bound by the COPPA clock, so growth flattens when expiry catches up with intake.',
        body: line('mgb', { title: 'Media volume', x, series: [{ name: 'actual GB', v: pad(D.mediaGB, fc(D.mediaGB)).act, color: 'var(--c5)' }, { name: 'linear forecast', v: pad(D.mediaGB, fc(D.mediaGB)).fc, color: 'var(--c5)', dash: true }], fmt: (v) => N(v, 1), unit: ' GB', h: 130 }) + `<p style="margin-top:6px;color:var(--ink-2)">Forecast +30 d: <strong>${N(fc(D.mediaGB)[29], 1)} GB</strong> of ${D.P ? 200 : 20} GB</p>` })}</div></div>
    <div class="grid"><div class="s5">${panel({ title: 'Replica readiness', sub: 'drag to see connection math', status: 'proposed', src: 'derived from DB_POOL_MAX and compose files',
      body: `<div class="field"><label for="rep">Server replicas: <strong>${rep}</strong></label><input id="rep" type="range" min="1" max="6" value="${rep}" data-act="replicas" data-fid="rep" style="width:100%"></div><div class="meter" role="meter" aria-valuemin="0" aria-valuemax="${maxc}" aria-valuenow="${conns}" aria-label="Postgres connections"><i class="${conns > 80 ? 'crit' : conns > 50 ? 'warn' : ''}" style="width:${conns}%"></i></div><dl class="kv"><dt>server pools</dt><dd>${rep} x 10</dd><dt>scheduler + migrate + backup</dt><dd>~12</dd><dt>total of max_connections ${maxc}</dt><dd><strong>${conns}</strong></dd></dl>` })}
      ${panel({ title: 'Cost', sub: 'monthly, sample', status: 'proposed', src: 'billing export; none connected', cls: '',
        body: table('cost', [{ k: 'l', label: 'Line' }, { k: 'usd', label: 'USD / mo', num: true, f: (r) => '$' + N(r.usd, 2) }], [{ l: 'Compute (1 VM)', usd: 48 }, { l: 'Postgres volume', usd: 12 }, { l: 'Media volume', usd: 20 }, { l: 'Off-host backup', usd: 6.4 }, { l: 'Egress', usd: 9.1 }, { l: 'Push provider', usd: 0 }], { caption: 'Cost' }) + `<p style="margin-top:8px"><strong>$${N(95.5 / D.fam.a24, 2)}</strong> per active family (24 h basis)</p>` })}</div>
      <div class="s7">${panel({ title: 'What breaks with two replicas', sub: 'read from the code, not guessed', status: 'partial', src: 'server/rate_limit.mjs, server/game_tables.mjs, server/observability.mjs, server/signed_media.mjs, tools/scheduler.mjs',
        why: 'Olive is a single-process server today. Most state is in memory by design (tables are meant to be ephemeral). This list says which of those choices become bugs the moment a second process appears.',
        body: table('rep', [{ k: 'c', label: 'Component' }, { k: 'now', label: 'Today', nosort: true, f: (r) => `<span style="color:var(--ink-2)">${esc(r.now)}</span>` }, { k: 'eff', label: 'With 2+ replicas', nosort: true, f: (r) => `${st(r.k === 'ok' ? 'ok' : r.k === 'risk' ? 'crit' : 'warn', r.k === 'ok' ? 'safe' : r.k === 'risk' ? 'breaks' : 'degrades')} ${esc(r.eff)}` }, { k: 'fix', label: 'Fix', nosort: true, f: (r) => esc(r.fix) }], rows.map(([c, now, eff, k, fix]) => ({ c, now, eff, k, fix })), { caption: 'Two-replica risks' }) })}</div></div>`;
};

V.settings = () => {
  const roles = ['viewer', 'responder', 'admin', 'auditor'];
  const perms = [['Read dashboards', [1, 1, 1, 1]], ['Acknowledge alerts', [0, 1, 1, 0]], ['Run a job', [0, 1, 1, 0]], ['Declare / resolve incident', [0, 1, 1, 0]], ['Toggle a flag', [0, 0, 1, 0]], ['Start a restore (scratch)', [0, 0, 1, 0]], ['Start a restore (prod)', [0, 0, 0, 0]], ['Open a support case', [0, 1, 1, 0]], ['Read operator audit log', [0, 0, 1, 1]], ['Manage operators and tokens', [0, 0, 1, 0]]];
  return head('Settings', 'Operators, roles, tokens and alert routing', 'Everything here is itself audited. Production restore appears in no role on purpose: it needs a second approver and an incident, not a standing permission.') +
    `<div class="grid"><div class="s6">${panel({ title: 'Operators', status: 'proposed', src: 'no operator identity exists; sign-in would reuse WebAuthn (0008)', why: 'Operators should sign in with passkeys, never shared accounts. Sample people.',
      body: table('ops', [{ k: 'n', label: 'Operator' }, { k: 'r', label: 'Role', f: (o) => `<span class="chip">${o.r}</span>` }, { k: 'p', label: 'Passkey', f: (o) => st('ok', 'yes') }, { k: 'l', label: 'Last sign-in', f: (o) => o.l }], [{ n: 'm.okafor', r: 'admin', l: 'now' }, { n: 'o.baker', r: 'responder', l: '3 h ago' }, { n: 'r.singh', r: 'auditor', l: '2 d ago' }, { n: 'j.lindqvist', r: 'viewer', l: '11 d ago' }], { caption: 'Operators' }) })}</div>
      <div class="s6">${panel({ title: 'Roles', status: 'proposed', src: 'proposed permission matrix', why: 'Least privilege, with auditing as a separate role from administration.',
        body: `<div class="tw"><table><caption class="sr">Role permissions</caption><thead><tr><th scope="col">Permission</th>${roles.map((r) => `<th scope="col" class="num">${r}</th>`).join('')}</tr></thead><tbody>${perms.map(([p, v]) => `<tr><th scope="row" style="text-transform:none;letter-spacing:0;font-weight:500;color:var(--ink);font-size:13px;position:static">${p}</th>${v.map((x) => `<td class="num">${x ? '<span class="st ok" aria-label="allowed">' + ic('i-ok', 14) + '</span>' : '<span style="color:var(--ink-3)" aria-label="not allowed">&ndash;</span>'}</td>`).join('')}</tr>`).join('')}</tbody></table></div>` })}</div></div>
    <div class="grid"><div class="s6">${panel({ title: 'API tokens', status: 'partial', src: 'INTERNAL_METRICS_TOKEN (single shared secret) is built; scoped, expiring tokens are proposed', actions: '<button class="btn sm" data-act="newtoken">New token</button>',
      why: 'Today one shared token gates /internal/metrics. Scoped tokens let a scraper read metrics without being able to run a job.',
      body: table('tok', [{ k: 'n', label: 'Token', mono: true }, { k: 's', label: 'Scope', mono: true }, { k: 'u', label: 'Last used' }, { k: 'e', label: 'Expires', mono: true }], [{ n: 'tok_prom_scrape', s: 'metrics:read', u: '12 s ago', e: dstr(Date.now() + 80 * 86400000) }, { n: 'tok_ci_deploy', s: 'migrations:read', u: '2 d ago', e: dstr(Date.now() + 20 * 86400000) }], { caption: 'API tokens' }) })}</div>
      <div class="s6">${panel({ title: 'Alert routing', status: 'proposed', src: 'tools/health-alert.mjs detects and exits non-zero; no email, Slack or pager integration exists anywhere in the repo', actions: '<button class="btn sm" data-act="testalert">Send test alert</button>',
        why: 'The honest gap: nothing pages anyone. This is the table that would close it: severity to channel, with quiet hours that never silence critical.',
        body: table('route', [{ k: 'sev', label: 'Severity' }, { k: 'ch', label: 'Channel' }, { k: 'q', label: 'Quiet hours' }], [{ sev: 'critical (health_check)', ch: 'pager + SMS', q: 'never muted' }, { sev: 'high', ch: 'chat + email', q: '22:00-07:00' }, { sev: 'backup_stale', ch: 'chat + email', q: '22:00-07:00' }, { sev: 'burn rate 14.4x / 6x', ch: 'pager', q: 'never muted' }], { caption: 'Alert routing' }) })}</div></div>
    <div class="grid"><div class="s12">${panel({ title: 'Redaction policy', status: 'proposed', src: 'enforced by construction: the console API would have no endpoint that returns these', why: 'The console is safe because it cannot show these, not because it chooses not to.',
      body: `<div class="split"><div><h3>Never shown</h3><ul style="color:var(--ink-2);padding-left:18px"><li>Message, letter, journal and care-note content</li><li>Photos, video, audio, any media bytes</li><li>Medical records, medications, doses, emergency card</li><li>Names of children and guardians, addresses, emails</li><li>Credentials, pairing codes, session tokens, IPs</li></ul></div><div><h3>Shown</h3><ul style="color:var(--ink-2);padding-left:18px"><li>Counts, states, durations, sizes</li><li>Family and request ids, truncated or hashed</li><li>Route templates and SQL fingerprints (placeholders only)</li><li>Pass / fail of integrity checks</li></ul></div></div>` })}</div></div>`;
};

// ---------------------------------------------------------------- render + router
function renderNav() {
  const hc = D ? healthCounts() : { breach: 0 };
  $('#nav').innerHTML = SECTIONS.map((g) => `<div class="nav-group">${g.g}</div>${g.items.map(([k, l, key]) => `<a href="#/${k}" ${k === state.route ? 'aria-current="page"' : ''} title="Go to ${l} (g then ${key})">${ic('n-' + (k === 'jobs' ? 'jobs' : k), 16)}<span>${l}</span>${k === 'health' && hc.breach ? `<span class="pip">${hc.breach}</span>` : ''}${k === 'incidents' && state.incident ? '<span class="pip">1</span>' : ''}${k === 'security' && state.faults.pairing ? '<span class="pip">1</span>' : ''}</a>`).join('')}`).join('');
}
function renderBanner() {
  const b = $('#incidentBanner'); const inc = state.incident;
  b.innerHTML = inc ? `<div class="banner crit" role="alert">${ic('i-crit')}<div class="grow"><strong>${inc.sev} active: ${esc(inc.title)}</strong> &middot; declared ${agoS(inc.t)} by ${esc(inc.by)}</div><a class="btn sm" href="#/incidents">Open incident</a></div>`
    : (state.env === 'prod' ? '' : '');
}
function render(keepScroll) {
  const y = window.scrollY; const fid = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.fid : null;
  uid = 0; data(); renderNav(); renderBanner();
  document.body.dataset.env = state.env;
  $('#view').innerHTML = (V[state.route] || V.overview)();
  if (keepScroll) window.scrollTo(0, y);
  if (fid) { const el = $(`[data-fid="${fid}"]`); if (el) el.focus({ preventScroll: true }); }
  $$('[data-chart].plot').forEach((p) => { if (p.dataset.restore) moveCursor(p, +p.dataset.restore); });
  document.title = `${(FLAT.find((s) => s.k === state.route) || {}).l || 'Console'} · Olive operator console (sample)`;
}
function route() {
  const k = (location.hash.replace(/^#\/?/, '').split('/')[0]) || 'overview';
  state.route = V[k] ? k : 'overview'; render(false);
  $('#side').classList.remove('open'); $('#scrim').hidden = true; $('#navToggle').setAttribute('aria-expanded', 'false');
  const v = $('#view'); v.focus({ preventScroll: true }); window.scrollTo(0, 0);
}

// ---------------------------------------------------------------- dialogs
const dlg = $('#dlg');
function openDlg(html, cls = '') { dlg.className = cls; dlg.innerHTML = html; if (!dlg.open) dlg.showModal(); }
function closeDlg() { if (dlg.open) dlg.close(); }
dlg.addEventListener('click', (e) => { if (e.target === dlg) closeDlg(); });
const dhead = (t, sub) => `<div class="dlg-h"><div><h2 id="dlgTitle">${t}</h2>${sub ? `<p style="color:var(--ink-3);margin-top:2px">${sub}</p>` : ''}</div><button class="icon-btn" data-act="closedlg" aria-label="Close dialog">${ic('i-x')}</button></div>`;

function privacyDialog() {
  openDlg(dhead('Privacy contract', 'What an operator can and cannot see in this console') + `<div class="dlg-b"><div class="split"><div><h3>Never</h3><ul style="padding-left:18px;color:var(--ink-2)"><li>message, letter, journal or care-note content</li><li>photos, video, audio</li><li>medical details</li><li>names of children</li><li>credentials, codes, tokens</li></ul></div><div><h3>Only</h3><ul style="padding-left:18px;color:var(--ink-2)"><li>counts, states, timings</li><li>ids hashed or truncated</li><li>pass / fail of integrity checks</li><li>health and capacity</li></ul></div></div><p style="margin-top:12px">${notice('info', 'Every operator action (runs, toggles, exports, support-case entry) is recorded with a reason in a hash-chained operator log.')}</p></div><div class="dlg-f"><button class="btn primary" data-act="closedlg">Understood</button></div>`);
}
function declareDialog() {
  openDlg(dhead('Declare an incident', 'Declare early. You can downgrade or resolve later.') + `<div class="dlg-b">
    <div class="field"><label for="incT">Title</label><input id="incT" type="text" placeholder="Short, factual, no personal data" autocomplete="off" data-fid="incT"></div>
    <div class="field"><span class="lab">Severity</span><div class="row"><label><input type="radio" name="sev" value="SEV1">SEV1 outage</label><label><input type="radio" name="sev" value="SEV2" checked>SEV2 degraded</label><label><input type="radio" name="sev" value="SEV3">SEV3 minor</label></div></div>
    <div class="field"><span class="lab">Affected areas (status page components)</span><div class="row"><label><input type="checkbox" name="area" value="delivery">Delivery</label><label><input type="checkbox" name="area" value="security">Sign-in</label><label><input type="checkbox" name="area" value="realtime">Game tables</label><label><input type="checkbox" name="area" value="storage">Photos and video</label></div></div>
    <div class="field"><label for="incS">Summary</label><textarea id="incS" data-fid="incS" placeholder="What we know. Counts and states only."></textarea><div id="lint" class="hint" aria-live="polite"></div></div>
    </div><div class="dlg-f"><button class="btn" data-act="closedlg">Cancel</button><button class="btn danger" data-act="doDeclare">Declare incident</button></div>`);
}
const LINT = [[/[\w.+-]+@[\w-]+\.[\w.]+/, 'looks like an email address'], [/\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b/, 'looks like a phone number'], [/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, 'full uuid: use the first 8 characters'], [/\b(said|wrote|message(d)? (says|said)|text of)\b/i, 'may quote content: describe counts and states instead']];
function lintText(t) { return LINT.filter(([re]) => re.test(t)).map(([, m]) => m); }
function runDialog(name) {
  const j = D.jobs.find((x) => x.name === name); const destructive = name === 'reap-media' || name === 'backup';
  openDlg(dhead(`Run ${name}`, 'Manual run. Takes the same advisory lock as the scheduler.') + `<div class="dlg-b">
    ${notice('info', esc(j.desc))}
    <p style="margin:10px 0">${name === 'reap-media' ? notice('warn', '<strong>Irreversible:</strong> deletes expired blobs and their rows.') : name === 'backup' ? notice('warn', 'Writes a new dump, prunes to 7 daily + 4 weekly and may sync off-host.') : ''}</p>
    <div class="field"><label for="runR">Reason (required, audited)</label><textarea id="runR" data-fid="runR" placeholder="e.g. post-migration sweep"></textarea><div id="runErr" class="hint" style="color:var(--crit)" role="alert"></div></div>
    ${destructive ? `<div class="field"><label for="runC">Type <code>${name}</code> to confirm</label><input id="runC" type="text" autocomplete="off" data-fid="runC"></div>` : ''}
    <label><input type="checkbox" id="runDry" disabled> Dry run <span class="src src-proposed" style="margin-left:6px">proposed: not built yet</span></label>
    </div><div class="dlg-f"><button class="btn" data-act="closedlg">Cancel</button><button class="btn primary" data-act="doRun" data-j="${name}" data-d="${destructive ? 1 : 0}">${ic('i-play', 12)}Run ${name}</button></div>`);
}
function checkDialog(k) {
  const r = D.hv.find((x) => x.name === k); const rb = O.RUNBOOKS.find((x) => x.key === k) || O.RUNBOOKS[0];
  openDlg(dhead(`<span class="mono">${k}</span>`, `${r.sev} &middot; ${r.breach ? 'breached' : 'within threshold'}`) + `<div class="dlg-b"><p>${esc(r.meaning)}</p>
    <dl class="kv" style="margin:12px 0"><dt>observed</dt><dd>${r.observed}</dd><dt>threshold</dt><dd>${r.threshold}</dd><dt>defined by</dt><dd class="mono">${esc(r.from)}</dd><dt>read by</dt><dd class="mono">tools/health-alert.mjs</dd></dl>
    <h3>Runbook: ${esc(rb.title)} ${src(rb.status)}</h3><ol class="steps" style="margin:8px 0">${rb.steps.slice(0, 4).map((s) => `<li><span>${esc(s)}</span></li>`).join('')}</ol></div>
    <div class="dlg-f"><a class="btn" href="#/incidents" data-act="closedlg">Open runbooks</a><button class="btn" data-act="ackcheck" data-k="${k}">${state.ack[k] ? 'Acknowledged' : 'Acknowledge (audited)'}</button></div>`);
}
function viewsDialog() {
  const presets = [['Morning check', 'overview', 'prod', '24h'], ['Delivery incident', 'delivery', 'prod', '1h'], ['Security sweep', 'security', 'prod', '7d'], ['Backups and drills', 'backups', 'prod', '30d']];
  const all = presets.concat(state.savedViews.map((v) => [v.name, v.route, v.env, v.range, true]));
  openDlg(dhead('Saved views', 'A view is a section, environment and time range.') + `<div class="dlg-b"><ul style="list-style:none;padding:0;margin:0;display:grid;gap:6px">${all.map((v, i) => `<li class="row" style="justify-content:space-between"><button class="btn" data-act="applyview" data-i="${i}">${esc(v[0])}</button><span class="mono" style="color:var(--ink-3)">${v[1]} &middot; ${v[2]} &middot; ${v[3]}${v[4] ? ' &middot; yours' : ''}</span></li>`).join('')}</ul>
    <div class="field" style="margin-top:14px"><label for="vn">Save current view as</label><div class="row"><input id="vn" type="text" placeholder="Name" style="flex:1" data-fid="vn"><button class="btn primary" data-act="saveview">Save</button></div></div></div>`);
  dlg._views = all;
}
function helpDialog() {
  openDlg(dhead('Keyboard shortcuts') + `<div class="dlg-b"><dl class="kv"><dt><kbd>Ctrl</kbd> <kbd>K</kbd> or <kbd>/</kbd></dt><dd>Command palette and search</dd><dt><kbd>g</kbd> then a letter</dt><dd>Jump to a section</dd><dt><kbd>?</kbd></dt><dd>This list</dd><dt><kbd>Esc</kbd></dt><dd>Close dialog</dd></dl>
    <div class="split" style="margin-top:12px">${FLAT.map((s) => `<span><kbd>g</kbd> <kbd>${s.key}</kbd> ${s.l}</span>`).join('')}</div></div>`);
}

// ---------------------------------------------------------------- palette
let palSel = 0; let palItems = [];
function paletteItems(q) {
  const items = [];
  FLAT.forEach((s) => items.push({ g: 'Go to', l: s.l, k: s.l + ' ' + s.k, run: () => { location.hash = '#/' + s.k; }, hint: 'g ' + s.key }));
  items.push({ g: 'Action', l: 'Declare incident', k: 'incident declare sev', run: declareDialog }, { g: 'Action', l: 'Toggle light / dark theme', k: 'theme dark light', run: toggleTheme }, { g: 'Action', l: 'Switch to prod', k: 'environment env production', run: () => setEnv('prod') }, { g: 'Action', l: 'Switch to dev', k: 'environment env development', run: () => setEnv('dev') }, { g: 'Action', l: 'Privacy contract', k: 'privacy redaction', run: privacyDialog }, { g: 'Action', l: 'Saved views', k: 'views bookmarks', run: viewsDialog }, { g: 'Action', l: 'Keyboard shortcuts', k: 'help keys', run: helpDialog });
  ['1h', '6h', '24h', '7d', '30d'].forEach((r) => items.push({ g: 'Time range', l: 'Set range ' + r, k: 'range time ' + r, run: () => setRange(r) }));
  D.jobs.filter((j) => j.built).forEach((j) => items.push({ g: 'Job', l: 'Run ' + j.name + ' (with confirm)', k: 'job run ' + j.name, run: () => { location.hash = '#/jobs'; setTimeout(() => runDialog(j.name), 50); } }));
  D.routes.forEach((r) => items.push({ g: 'Route', l: r.m + ' ' + r.r, k: 'route request ' + r.r, run: () => { state.selRoute = r.i; location.hash = '#/requests'; render(); } }));
  O.RUNBOOKS.forEach((r) => items.push({ g: 'Runbook', l: r.title, k: 'runbook ' + r.key, run: () => { location.hash = '#/incidents'; } }));
  [['stalled', 'Sample: inject stalled delivery'], ['errors', 'Sample: inject 5xx spike'], ['pairing', 'Sample: inject pairing brute force']].forEach(([k, l]) => items.push({ g: 'Sample', l, k: 'fault inject demo ' + k, run: () => { state.faults[k] = !state.faults[k]; render(true); toast(l, 'sample fault toggled'); } }));
  state.savedViews.forEach((v) => items.push({ g: 'View', l: v.name, k: 'view ' + v.name, run: () => applyView(v.route, v.env, v.range) }));
  const m = q.trim().toLowerCase();
  if (/^fam_[0-9a-f]{3,}/.test(m)) items.unshift({ g: 'Tenant', l: 'Open ' + m + ' in Tenants', k: m, run: () => { location.hash = '#/tenants'; } });
  if (!m) return items.filter((i) => i.g !== 'Route' && i.g !== 'Runbook').slice(0, 24);
  return items.filter((i) => (i.l + ' ' + i.k).toLowerCase().includes(m)).sort((a, b) => (b.l.toLowerCase().startsWith(m) ? 1 : 0) - (a.l.toLowerCase().startsWith(m) ? 1 : 0)).slice(0, 30);
}
function openPalette() {
  openDlg(`<div class="pal-in">${ic('i-search', 18)}<input id="palIn" type="text" role="combobox" aria-expanded="true" aria-controls="palList" aria-label="Search or run a command" placeholder="Jump to a section, run a command, find a route or family hash" autocomplete="off"><kbd>Esc</kbd></div><ul class="pal-list" id="palList" role="listbox" aria-label="Results"></ul>`, 'palette');
  palSel = 0; fillPalette(''); $('#palIn').focus();
}
function fillPalette(q) {
  palItems = paletteItems(q); palSel = 0; const ul = $('#palList'); let lastG = '';
  ul.innerHTML = palItems.length ? palItems.map((it, i) => { const hd = it.g !== lastG ? `<li class="hd" role="presentation">${it.g}</li>` : ''; lastG = it.g; return hd + `<li role="option" id="po${i}" data-i="${i}" aria-selected="${i === 0}">${esc(it.l)}<span class="grp">${it.hint || ''}</span></li>`; }).join('') : '<li class="hd" role="presentation">No results</li>';
  $('#palIn').setAttribute('aria-activedescendant', palItems.length ? 'po0' : '');
}
function palMove(d) { if (!palItems.length) return; palSel = (palSel + d + palItems.length) % palItems.length; $$('#palList [role=option]').forEach((li) => li.setAttribute('aria-selected', String(+li.dataset.i === palSel))); const el = $('#po' + palSel); el.scrollIntoView({ block: 'nearest' }); $('#palIn').setAttribute('aria-activedescendant', 'po' + palSel); }
function palRun(i) { const it = palItems[i]; if (!it) return; closeDlg(); setTimeout(() => it.run(), 0); }

// ---------------------------------------------------------------- state changes
function setEnv(e) { state.env = e; store.set('env', e); $$('#envSeg button').forEach((b) => b.setAttribute('aria-checked', String(b.dataset.env === e))); state.devMetricsOk = false; render(true); toast(`Environment: ${e}`, e === 'prod' ? 'sample prod data; real prod would require re-authentication' : 'sample dev data'); }
function setRange(r) { state.range = r; store.set('range', r); $('#rangeSel').value = r; render(true); }
function applyView(rt, env, range) { state.env = env; state.range = range; $('#rangeSel').value = range; $$('#envSeg button').forEach((b) => b.setAttribute('aria-checked', String(b.dataset.env === env))); store.set('env', env); store.set('range', range); if (location.hash === '#/' + rt) render(); else location.hash = '#/' + rt; }
function applyTheme() {
  const t = state.theme; const root = document.documentElement;
  if (t) root.setAttribute('data-theme', t); else root.removeAttribute('data-theme');
  const dark = t ? t === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  $('#themeIcon').innerHTML = `<use href="#${dark ? 'i-sun' : 'i-moon'}"/>`;
}
function toggleTheme() { const dark = state.theme ? state.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches; state.theme = dark ? 'light' : 'dark'; store.set('theme', state.theme); applyTheme(); }

function simulateRun(name) {
  state.running = name; state.runLog = [`<span class="k">scope=scheduler event=start job=${name} at=${new Date().toISOString()} trigger=manual operator=m.okafor</span>`];
  render(true);
  const j = D.jobs.find((x) => x.name === name); const steps = [`scope=scheduler event=lock job=${name} acquired=true`, `scope=scheduler event=progress job=${name} phase=work`];
  steps.forEach((s, i) => setTimeout(() => { state.runLog.push(s); if (state.route === 'jobs') render(true); }, 700 * (i + 1)));
  setTimeout(() => { state.runLog.push(`scope=scheduler event=end job=${name} status=<span class="g">ok</span> duration_ms=${Math.round(j.dur * 0.9)} ${esc(j.fieldsStr)} at=${new Date().toISOString()}`); state.running = null; if (state.route === 'jobs') render(true); toast(`${name} finished: ok`, 'sample run; nothing executed'); }, 2300);
}

// ---------------------------------------------------------------- actions
const ACT = {
  closedlg: () => closeDlg(),
  goto: (el) => { location.hash = '#/' + el.dataset.to; },
  tab: (el) => { state.tabs[el.dataset.n] = el.dataset.k; render(true); },
  sort: (el) => { const id = el.dataset.t; const cur = state.sort[id] || TB[id].o.sort || {}; state.sort[id] = { k: el.dataset.k, dir: cur.k === el.dataset.k && cur.dir === 'asc' ? 'desc' : (cur.k === el.dataset.k ? 'asc' : (TB[id].cols.find((c) => c.k === el.dataset.k).num ? 'desc' : 'asc')) }; $('#tw-' + id).innerHTML = tableInner(id); const b = $(`[data-fid="th-${id}-${el.dataset.k}"]`); if (b) b.focus(); },
  fault: (el) => { const k = el.dataset.k; state.faults[k] = !state.faults[k]; render(true); toast(`Sample fault ${state.faults[k] ? 'injected' : 'cleared'}: ${k}`, 'mockup control only'); },
  recheck: () => { render(true); toast('health_check re-run', 'SELECT ... FROM health_check (read-only)'); },
  check: (el) => checkDialog(el.dataset.k),
  ackcheck: (el) => { state.ack[el.dataset.k] = true; audited('alert.ack', el.dataset.k, 'acknowledged from health board', 'Acknowledged ' + el.dataset.k); closeDlg(); },
  devtoken: () => { state.devMetricsOk = true; render(true); },
  route: (el) => { state.selRoute = el.dataset.i === '' ? null : +el.dataset.i; render(true); if (state.selRoute != null) $('#view').scrollTo?.(0, 0); },
  cell: (el) => { state.selJob = { j: el.dataset.j, d: +el.dataset.d }; render(true); },
  runjob: (el) => runDialog(el.dataset.j),
  doRun: (el) => {
    const r = $('#runR').value.trim(); const err = $('#runErr');
    if (r.length < 10) { err.textContent = 'Give a reason of at least 10 characters.'; $('#runR').focus(); return; }
    if (el.dataset.d === '1' && $('#runC').value.trim() !== el.dataset.j) { err.textContent = `Type ${el.dataset.j} to confirm.`; $('#runC').focus(); return; }
    const lint = lintText(r); if (lint.length) { err.textContent = 'Reason ' + lint[0] + '.'; return; }
    closeDlg(); audited('job.run', el.dataset.j, r, `Started ${el.dataset.j}`); simulateRun(el.dataset.j);
  },
  verify: () => { state.verifyRun++; render(true); audited('audit.verify', 'all chains', 'operator-initiated integrity sweep', 'Verified all family hash chains: pass'); },
  declare: () => declareDialog(),
  doDeclare: () => {
    const title = $('#incT').value.trim(); const sum = $('#incS').value.trim(); const lint = lintText(title + ' ' + sum);
    if (!title) { $('#lint').textContent = 'A title is required.'; $('#incT').focus(); return; }
    if (lint.length) { $('#lint').textContent = 'Please remove: ' + lint.join('; ') + '.'; $('#lint').style.color = 'var(--crit)'; return; }
    const sev = $('input[name=sev]:checked').value; const areas = $$('input[name=area]:checked').map((x) => x.value);
    state.incident = { id: 'INC-0004', sev, title, by: 'm.okafor', t: Date.now(), areas, events: [{ k: 'crit', t: Date.now(), text: `Declared ${sev}: ${title}` }, ...(sum ? [{ k: '', t: Date.now(), text: sum }] : []), { k: '', t: Date.now(), text: 'Status page updated; relevant runbooks opened.' }] };
    closeDlg(); audited('incident.declare', 'INC-0004', `${sev}: ${title}`, `Incident declared (${sev})`); location.hash = '#/incidents'; render(true);
  },
  resolve: () => { const i = state.incident; i.events.unshift({ k: 'ok', t: Date.now(), text: 'Resolved' }); state.incidents.unshift({ id: i.id, sev: i.sev, t: i.t, title: i.title, area: i.areas.join(', ') || 'general', mins: Math.max(1, Math.round((Date.now() - i.t) / 60000)) }); state.incident = null; audited('incident.resolve', i.id, 'resolved from console', 'Incident resolved'); render(true); },
  flag: (el) => { const f = state.flags.find((x) => x.k === el.dataset.k); openDlg(dhead(`Turn ${f.on ? 'off' : 'on'} ${f.k}`, 'Flag changes are audited.') + `<div class="dlg-b">${f.built === 'proposed' ? notice('warn', 'This flag has no server-side backing today. In the real console this row would not be toggleable until it does.') : ''}<div class="field" style="margin-top:10px"><label for="flR">Reason</label><textarea id="flR" data-fid="flR"></textarea><div id="flE" class="hint" style="color:var(--crit)"></div></div></div><div class="dlg-f"><button class="btn" data-act="closedlg">Cancel</button><button class="btn primary" data-act="doFlag" data-k="${f.k}">Apply</button></div>`); },
  doFlag: (el) => { const r = $('#flR').value.trim(); if (r.length < 5) { $('#flE').textContent = 'A reason is required.'; return; } const f = state.flags.find((x) => x.k === el.dataset.k); f.on = !f.on; closeDlg(); audited('flag.set', f.k + '=' + (f.on ? 'on' : 'off'), r, `${f.k} is now ${f.on ? 'on' : 'off'}`); render(true); },
  rpick: (el) => { state.restore.pick = +el.dataset.i; state.restore.dry = null; },
  rtarget: (el) => { state.restore.target = el.dataset.v; state.restore.dry = null; render(true); },
  rstep: (el) => { state.restore.step = Math.max(0, Math.min(3, state.restore.step + +el.dataset.d)); render(true); },
  rdry: () => {
    const f = D.files[state.restore.pick]; state.restore.dry = [];
    const lines = [['Locate and read header', f.name], ['Decrypt (AES-256-GCM tag check)', 'auth tag valid; passphrase from secret store'], ['pg_restore --list', 'catalog readable, 38 tables, 0 errors'], ['Checksum vs manifest', 'sha256 matches olive_*.sha256'], ['Row-count manifest vs last verify', 'all within +/- 0.5%'], ['Estimate', 'about 4 min restore, 190 MB, scratch target only']];
    lines.forEach((l, i) => setTimeout(() => { state.restore.dry.push({ t: l[0], d: l[1], ok: true }); if (state.route === 'backups') render(true); if (i === lines.length - 1) toast('Dry run passed', 'nothing was written'); }, 350 * (i + 1)));
  },
  rgo: () => { const ph = $('#rph').value.trim(); const need = 'restore ' + (state.restore.target === 'prod' ? 'prod' : 'scratch'); const rs = $('#rrs').value.trim(); if (ph !== need || rs.length < 10) { toast('Type the phrase and give a reason', 'both are required'); return; } if (state.restore.target === 'prod') { toast('Needs second approver', 'o.baker must approve (sample control)'); return; } audited('restore.scratch', D.files[state.restore.pick].name, rs, 'Scratch restore started'); state.restore = { step: 0, pick: 0, target: 'scratch', dry: null }; render(true); },
  grantcase: () => { state.supportCase = 1; audited('support.consent', 'c_91a2', 'guardian approved in app (60 min, flags+counters)', 'Consent received; time-boxed access active'); render(true); },
  revokecase: () => { state.supportCase = 0; audited('support.end', 'c_91a2', 'operator ended access early', 'Access ended'); render(true); },
  famfilter: (el) => { state.familyFilter = el.value; render(true); },
  replicas: (el) => { state.replicas = +el.value; render(true); },
  newtoken: () => openDlg(dhead('New API token') + `<div class="dlg-b"><div class="field"><label for="tkN">Name</label><input id="tkN" type="text" data-fid="tkN"></div><div class="field"><label for="tkS">Scope</label><select id="tkS" class="in"><option>metrics:read</option><option>migrations:read</option><option>audit:read</option></select></div>${notice('info', 'The secret is shown once. This mockup would show a clearly fake <code>ob_sample_...</code> string, never a working token.')}</div><div class="dlg-f"><button class="btn" data-act="closedlg">Cancel</button><button class="btn primary" data-act="mktoken">Create</button></div>`),
  mktoken: () => { const n = $('#tkN').value.trim() || 'tok_unnamed'; closeDlg(); audited('token.create', n, 'created from settings', 'Token created: ob_sample_SHOWN_ONCE'); },
  testalert: () => audited('alert.test', 'routing', 'test fire from settings', 'Test alert queued (no channel is integrated)'),
  applyview: (el) => { const v = dlg._views[+el.dataset.i]; closeDlg(); applyView(v[1], v[2], v[3]); },
  saveview: () => { const n = $('#vn').value.trim(); if (!n) { $('#vn').focus(); return; } state.savedViews.push({ name: n, route: state.route, env: state.env, range: state.range }); store.set('views', state.savedViews); closeDlg(); toast('View saved', `${n}: ${state.route}, ${state.env}, ${state.range}`); },
};

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]'); if (el && ACT[el.dataset.act] && el.tagName !== 'SELECT' && el.type !== 'range' && el.type !== 'radio') { if (el.tagName === 'A' && el.dataset.act === 'closedlg') closeDlg(); else { e.preventDefault?.(); ACT[el.dataset.act](el); } return; }
  if (el && el.type === 'radio' && ACT[el.dataset.act]) { ACT[el.dataset.act](el); return; }
  const li = e.target.closest('#palList [role=option]'); if (li) palRun(+li.dataset.i);
});
document.addEventListener('change', (e) => { const el = e.target.closest('select[data-act],input[type=range][data-act]'); if (el) ACT[el.dataset.act](el); });
document.addEventListener('input', (e) => {
  if (e.target.id === 'palIn') fillPalette(e.target.value);
  if (e.target.id === 'routeFilter') { state.routeFilter = e.target.value; $('#tw-routes').innerHTML = tableInner('routes'); }
  if (e.target.id === 'incS' || e.target.id === 'incT') { const l = lintText($('#incT').value + ' ' + $('#incS').value); const el = $('#lint'); el.textContent = l.length ? 'Privacy lint: ' + l.join('; ') : ''; el.style.color = l.length ? 'var(--warn)' : ''; }
  if (e.target.id === 'rep') { const v = +e.target.value; state.replicas = v; render(true); }
});
// chart pointer + keyboard
document.addEventListener('pointermove', (e) => { const p = e.target.closest('.plot'); if (!p || !CH[p.dataset.chart]) return; const r = p.getBoundingClientRect(); const c = CH[p.dataset.chart]; moveCursor(p, Math.round((e.clientX - r.left) / r.width * (c.x.length - 1))); });
document.addEventListener('pointerleave', (e) => { if (e.target.classList && e.target.classList.contains('plot')) e.target.classList.remove('on'); }, true);
document.addEventListener('keydown', (e) => {
  const p = e.target.closest && e.target.closest('.plot');
  if (p && (e.key === 'ArrowLeft' || e.key === 'ArrowRight' || e.key === 'Home' || e.key === 'End')) { e.preventDefault(); const c = CH[p.dataset.chart]; let i = p.dataset.idx != null ? +p.dataset.idx : c.x.length - 1; i = e.key === 'Home' ? 0 : e.key === 'End' ? c.x.length - 1 : i + (e.key === 'ArrowRight' ? 1 : -1); moveCursor(p, i); return; }
  if (p && e.key === 'Escape') { p.classList.remove('on'); return; }
  const inField = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName);
  if (dlg.open && e.target.id === 'palIn') {
    if (e.key === 'ArrowDown') { e.preventDefault(); palMove(1); } else if (e.key === 'ArrowUp') { e.preventDefault(); palMove(-1); } else if (e.key === 'Enter') { e.preventDefault(); palRun(palSel); }
    return;
  }
  if ((e.key === 'k' || e.key === 'K') && (e.ctrlKey || e.metaKey)) { e.preventDefault(); openPalette(); return; }
  if (inField || dlg.open || e.ctrlKey || e.metaKey || e.altKey) return;
  if (e.key === '/') { e.preventDefault(); openPalette(); return; }
  if (e.key === '?') { helpDialog(); return; }
  if (gSeq && (Date.now() - gSeq < 1200)) { const s = FLAT.find((x) => x.key === e.key); gSeq = 0; if (s) { location.hash = '#/' + s.k; return; } }
  if (e.key === 'g') gSeq = Date.now();
});
let gSeq = 0;

// ---------------------------------------------------------------- chrome wiring
$('#searchBtn').addEventListener('click', openPalette);
$('#themeBtn').addEventListener('click', toggleTheme);
$('#privacyBtn').addEventListener('click', privacyDialog);
$('#viewsBtn').addEventListener('click', viewsDialog);
$('#declareBtn').addEventListener('click', declareDialog);
$('#envSeg').addEventListener('click', (e) => { const b = e.target.closest('button[data-env]'); if (b) setEnv(b.dataset.env); });
$('#rangeSel').addEventListener('change', (e) => setRange(e.target.value));
$('#navToggle').addEventListener('click', () => { const o = $('#side').classList.toggle('open'); $('#scrim').hidden = !o; $('#navToggle').setAttribute('aria-expanded', String(o)); if (o) $('#nav a').focus(); });
$('#scrim').addEventListener('click', () => { $('#side').classList.remove('open'); $('#scrim').hidden = true; $('#navToggle').setAttribute('aria-expanded', 'false'); });
$('#side').addEventListener('keydown', (e) => { if (e.key === 'Escape') { $('#side').classList.remove('open'); $('#scrim').hidden = true; $('#navToggle').focus(); } });
window.addEventListener('hashchange', route);
matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', applyTheme);
setInterval(() => {
  $$('[data-live=age]').forEach((el) => { el.textContent = Math.round((Date.now() - +el.dataset.t) / 1000) + 's'; });
  $$('[data-countdown]').forEach((el) => { const s = Math.max(0, Math.round((+el.dataset.countdown - Date.now()) / 1000)); el.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; });
}, 1000);

seedAudit(); applyTheme();
$$('#envSeg button').forEach((b) => b.setAttribute('aria-checked', String(b.dataset.env === state.env)));
$('#rangeSel').value = state.range;
route();
})();
